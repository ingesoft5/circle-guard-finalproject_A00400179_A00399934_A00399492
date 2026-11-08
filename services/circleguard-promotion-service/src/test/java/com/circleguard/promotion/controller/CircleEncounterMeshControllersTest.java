package com.circleguard.promotion.controller;

import com.circleguard.promotion.model.graph.CircleNode;
import com.circleguard.promotion.repository.graph.UserNodeRepository;
import com.circleguard.promotion.service.AutoCircleService;
import com.circleguard.promotion.service.CircleService;
import com.circleguard.promotion.service.LocationResolutionService;
import com.circleguard.promotion.service.MacSessionRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Circles, encounters, mesh statistics, device sessions and Wi-Fi location signals. */
@ExtendWith(MockitoExtension.class)
class CircleEncounterMeshControllersTest {

    @Mock
    private CircleService circleService;
    @Mock
    private UserNodeRepository userRepository;
    @Mock
    private AutoCircleService autoCircleService;
    @Mock
    private MacSessionRegistry sessionRegistry;
    @Mock
    private LocationResolutionService locationService;

    private MockMvc circles;
    private MockMvc encounters;
    private MockMvc mesh;
    private MockMvc sessions;
    private MockMvc location;

    @BeforeEach
    void setUp() {
        circles = MockMvcBuilders.standaloneSetup(new CircleController(circleService)).build();
        encounters = MockMvcBuilders.standaloneSetup(new EncounterController(userRepository, autoCircleService)).build();
        mesh = MockMvcBuilders.standaloneSetup(new MeshController(userRepository)).build();
        sessions = MockMvcBuilders.standaloneSetup(new SessionHandshakeController(sessionRegistry)).build();
        location = MockMvcBuilders.standaloneSetup(new LocationSignalController(locationService)).build();
    }

    private static CircleNode circle() {
        return CircleNode.builder().id(7L).name("Lab team").inviteCode("MESH-ABCD").locationId("lab-1").isActive(true).build();
    }

    // ---- CircleController ------------------------------------------------------------------------

    @Test
    void createCircle_ReturnsTheNewCircle() throws Exception {
        when(circleService.createCircle("Lab team", "lab-1")).thenReturn(circle());

        circles.perform(post("/api/v1/circles").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Lab team\",\"locationId\":\"lab-1\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.inviteCode").value("MESH-ABCD"));
    }

    @Test
    void joinCircle_UsesTheInviteCodeAndTheUser() throws Exception {
        when(circleService.joinCircle("anon-1", "MESH-ABCD")).thenReturn(circle());

        circles.perform(post("/api/v1/circles/join/{code}/user/{id}", "MESH-ABCD", "anon-1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Lab team"));
    }

    @Test
    void addMember_AddsTheUserToTheCircle() throws Exception {
        when(circleService.addMember(7L, "anon-2")).thenReturn(circle());

        circles.perform(post("/api/v1/circles/{id}/members/{user}", 7L, "anon-2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(7));
    }

    @Test
    void getUserCircles_ListsTheCirclesOfTheUser() throws Exception {
        when(circleService.getUserCircles("anon-1")).thenReturn(List.of(circle()));

        circles.perform(get("/api/v1/circles/user/{id}", "anon-1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].locationId").value("lab-1"));
    }

    @Test
    void circleValidityAndForceFence_Delegate() throws Exception {
        circles.perform(patch("/api/v1/circles/{id}/validity", 7L)).andExpect(status().isOk());
        circles.perform(post("/api/v1/circles/{id}/force-fence", 7L)).andExpect(status().isOk());

        verify(circleService).toggleCircleValidity(7L);
        verify(circleService).forceFenceCircle(7L);
    }

    // ---- EncounterController ---------------------------------------------------------------------

    @Test
    void reportEncounter_RecordsItAndEvaluatesTheAutoCircle() throws Exception {
        encounters.perform(post("/api/v1/encounters/report").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sourceId\":\"a\",\"targetId\":\"b\",\"locationId\":\"lab-1\"}"))
                .andExpect(status().isOk());

        verify(userRepository).recordEncounter(eq("a"), eq("b"), anyLong(), eq("lab-1"));
        verify(autoCircleService).evaluateEncounter("a", "b");
    }

    @Test
    void reportEncounter_WithoutLocation_DefaultsToMobileBle() throws Exception {
        encounters.perform(post("/api/v1/encounters/report").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sourceId\":\"a\",\"targetId\":\"b\"}"))
                .andExpect(status().isOk());

        verify(userRepository).recordEncounter(eq("a"), eq("b"), anyLong(), eq("mobile_ble"));
    }

    @Test
    void encounterValidityAndForceFence_Delegate() throws Exception {
        encounters.perform(patch("/api/v1/encounters/{id}/validity", 11L)).andExpect(status().isOk());
        encounters.perform(post("/api/v1/encounters/{id}/force-fence", 11L)).andExpect(status().isOk());

        verify(userRepository).toggleEncounterValidity(11L);
        verify(userRepository).forceEncounterFence(11L);
    }

    // ---- MeshController --------------------------------------------------------------------------

    @Test
    void meshStats_ReturnsConfirmedAndUnconfirmedConnections() throws Exception {
        when(userRepository.getConfirmedConnectionCount("anon-1")).thenReturn(4L);
        when(userRepository.getUnconfirmedConnectionCount("anon-1")).thenReturn(9L);

        mesh.perform(get("/api/v1/mesh/stats/{id}", "anon-1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.confirmedCount").value(4))
                .andExpect(jsonPath("$.unconfirmedCount").value(9));
    }

    // ---- SessionHandshakeController --------------------------------------------------------------

    @Test
    void handshake_RegistersTheDeviceSession() throws Exception {
        sessions.perform(post("/api/v1/sessions/handshake").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"macAddress\":\"AA:BB\",\"anonymousId\":\"anon-1\"}"))
                .andExpect(status().isOk());

        verify(sessionRegistry).registerSession("AA:BB", "anon-1");
    }

    @Test
    void handshake_MissingFields_Returns400() throws Exception {
        sessions.perform(post("/api/v1/sessions/handshake").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"macAddress\":\"AA:BB\"}"))
                .andExpect(status().isBadRequest());

        verify(sessionRegistry, never()).registerSession(anyString(), anyString());
    }

    @Test
    void closeSession_Returns204() throws Exception {
        sessions.perform(delete("/api/v1/sessions/{mac}", "AA:BB")).andExpect(status().isNoContent());

        verify(sessionRegistry).closeSession("AA:BB");
    }

    // ---- LocationSignalController ----------------------------------------------------------------

    @Test
    void locationSignal_IsPassedToTheResolutionService() throws Exception {
        location.perform(post("/api/v1/location/signal").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"apMac\":\"ap:01\",\"deviceMac\":\"dev:01\",\"rssi\":-55.5}"))
                .andExpect(status().isOk());

        verify(locationService).processSignal("ap:01", "dev:01", -55.5);
    }

    @Test
    void locationSignal_WithoutDeviceMac_Returns400() throws Exception {
        location.perform(post("/api/v1/location/signal").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"apMac\":\"ap:01\",\"rssi\":-55.5}"))
                .andExpect(status().isBadRequest());

        verify(locationService, never()).processSignal(anyString(), anyString(), anyDouble());
        verify(circleService, never()).createCircle(any(), any());
    }
}
