package com.circleguard.promotion.controller;

import com.circleguard.promotion.model.AccessPoint;
import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.model.Floor;
import com.circleguard.promotion.service.AccessPointService;
import com.circleguard.promotion.service.BuildingService;
import com.circleguard.promotion.service.FloorService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Buildings, floors and access points. Method security is covered separately by SpatialSecurityTest. */
@ExtendWith(MockitoExtension.class)
class SpatialControllersTest {

    @Mock
    private BuildingService buildingService;
    @Mock
    private FloorService floorService;
    @Mock
    private AccessPointService accessPointService;

    private MockMvc buildings;
    private MockMvc floors;
    private MockMvc accessPoints;

    private final UUID buildingId = UUID.randomUUID();
    private final UUID floorId = UUID.randomUUID();
    private final UUID apId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        buildings = MockMvcBuilders.standaloneSetup(new BuildingController(buildingService, floorService)).build();
        floors = MockMvcBuilders.standaloneSetup(new FloorController(floorService, accessPointService)).build();
        accessPoints = MockMvcBuilders.standaloneSetup(new AccessPointController(accessPointService)).build();
    }

    private Building building() {
        Floor floor = Floor.builder().id(floorId).floorNumber(1).name("Ground").floorPlanUrl("plan.png").build();
        return Building.builder().id(buildingId).name("Main").code("MAIN").description("d")
                .latitude(3.4).longitude(-76.5).address("Calle 1").floors(List.of(floor)).build();
    }

    private AccessPoint accessPoint() {
        Floor floor = Floor.builder().id(floorId).build();
        return AccessPoint.builder().id(apId).macAddress("aa:bb").floor(floor).coordinateX(1.0).coordinateY(2.0).name("AP-1").build();
    }

    // ---- BuildingController ----------------------------------------------------------------------

    @Test
    void createBuilding_ReturnsItsDataWithTheFloors() throws Exception {
        when(buildingService.createBuilding(eq("Main"), eq("MAIN"), eq("d"), eq(3.4), eq(-76.5), eq("Calle 1")))
                .thenReturn(building());

        buildings.perform(post("/api/v1/buildings").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Main\",\"code\":\"MAIN\",\"description\":\"d\",\"latitude\":3.4,\"longitude\":-76.5,\"address\":\"Calle 1\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("MAIN"))
                .andExpect(jsonPath("$.floors[0].name").value("Ground"))
                .andExpect(jsonPath("$.floors[0].floorPlanUrl").value("plan.png"));
    }

    @Test
    void listBuildings_ReturnsEveryBuilding_WithNullFloorsWhenNotLoaded() throws Exception {
        Building bare = Building.builder().id(buildingId).name("Lab").code("LAB").build();
        when(buildingService.getAllBuildings()).thenReturn(List.of(bare));

        buildings.perform(get("/api/v1/buildings"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("Lab"))
                .andExpect(jsonPath("$[0].floors").doesNotExist());
    }

    @Test
    void getFloors_ListsTheFloorsOfABuilding() throws Exception {
        Floor floor = Floor.builder().id(floorId).building(Building.builder().id(buildingId).build()).floorNumber(2).name("Two").build();
        when(floorService.getFloorsByBuilding(buildingId)).thenReturn(List.of(floor));

        buildings.perform(get("/api/v1/buildings/{id}/floors", buildingId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].buildingId").value(buildingId.toString()))
                .andExpect(jsonPath("$[0].floorNumber").value(2));
    }

    @Test
    void addFloor_CreatesAFloorInTheBuilding() throws Exception {
        Floor floor = Floor.builder().id(floorId).floorNumber(3).name("Three").build();
        when(floorService.addFloor(buildingId, 3, "Three")).thenReturn(floor);

        buildings.perform(post("/api/v1/buildings/{id}/floors", buildingId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"floorNumber\":3,\"name\":\"Three\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.floorNumber").value(3))
                .andExpect(jsonPath("$.buildingId").doesNotExist());
    }

    @Test
    void updateBuilding_ReturnsTheUpdatedData() throws Exception {
        when(buildingService.updateBuilding(eq(buildingId), eq("New"), eq("N"), eq("d2"), eq(1.0), eq(2.0), eq("addr")))
                .thenReturn(Building.builder().id(buildingId).name("New").code("N").build());

        buildings.perform(put("/api/v1/buildings/{id}", buildingId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"New\",\"code\":\"N\",\"description\":\"d2\",\"latitude\":1.0,\"longitude\":2.0,\"address\":\"addr\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("New"));
    }

    @Test
    void deleteBuilding_Delegates() throws Exception {
        buildings.perform(delete("/api/v1/buildings/{id}", buildingId)).andExpect(status().isOk());

        verify(buildingService).deleteBuilding(buildingId);
    }

    // ---- FloorController -------------------------------------------------------------------------

    @Test
    void addAccessPoint_RegistersItOnTheFloor() throws Exception {
        when(accessPointService.registerAccessPoint(eq(floorId), eq("aa:bb"), eq(1.0), eq(2.0), eq("AP-1")))
                .thenReturn(accessPoint());

        floors.perform(post("/api/v1/floors/{id}/access-points", floorId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"macAddress\":\"aa:bb\",\"coordinateX\":1.0,\"coordinateY\":2.0,\"name\":\"AP-1\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.floorId").value(floorId.toString()))
                .andExpect(jsonPath("$.macAddress").value("aa:bb"));
    }

    @Test
    void getAccessPoints_ListsThoseOfTheFloor() throws Exception {
        when(accessPointService.getAccessPointsByFloor(floorId)).thenReturn(List.of(accessPoint()));

        floors.perform(get("/api/v1/floors/{id}/access-points", floorId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("AP-1"));
    }

    @Test
    void updateFloor_ReturnsTheUpdatedFloor() throws Exception {
        when(floorService.updateFloor(floorId, 4, "Four", "four.png"))
                .thenReturn(Floor.builder().id(floorId).floorNumber(4).name("Four").floorPlanUrl("four.png").build());

        floors.perform(put("/api/v1/floors/{id}", floorId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"floorNumber\":4,\"name\":\"Four\",\"floorPlanUrl\":\"four.png\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.floorPlanUrl").value("four.png"));
    }

    @Test
    void deleteFloor_Delegates() throws Exception {
        floors.perform(delete("/api/v1/floors/{id}", floorId)).andExpect(status().isOk());

        verify(floorService).deleteFloor(floorId);
    }

    // ---- AccessPointController -------------------------------------------------------------------

    @Test
    void getAccessPoint_Found() throws Exception {
        when(accessPointService.getAccessPoint(apId)).thenReturn(Optional.of(accessPoint()));

        accessPoints.perform(get("/api/v1/access-points/{id}", apId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.coordinateX").value(1.0));
    }

    @Test
    void getAccessPoint_NotFound_Returns404() throws Exception {
        when(accessPointService.getAccessPoint(apId)).thenReturn(Optional.empty());

        accessPoints.perform(get("/api/v1/access-points/{id}", apId)).andExpect(status().isNotFound());
    }

    @Test
    void updateAccessPoint_ReturnsTheUpdatedPoint() throws Exception {
        when(accessPointService.updateAccessPoint(eq(apId), eq("cc:dd"), anyDouble(), anyDouble(), eq("renamed")))
                .thenReturn(AccessPoint.builder().id(apId).macAddress("cc:dd").coordinateX(5.0).coordinateY(6.0).name("renamed").build());

        accessPoints.perform(put("/api/v1/access-points/{id}", apId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"macAddress\":\"cc:dd\",\"coordinateX\":5.0,\"coordinateY\":6.0,\"name\":\"renamed\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("renamed"))
                .andExpect(jsonPath("$.floorId").doesNotExist());
    }

    @Test
    void deleteAccessPoint_Delegates() throws Exception {
        accessPoints.perform(delete("/api/v1/access-points/{id}", apId)).andExpect(status().isOk());

        verify(accessPointService).deleteAccessPoint(apId);
        verify(accessPointService, org.mockito.Mockito.never()).registerAccessPoint(any(), any(), any(), any(), any());
    }
}
