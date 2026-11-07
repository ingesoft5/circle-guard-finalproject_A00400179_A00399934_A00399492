package com.circleguard.auth.controller;

import com.circleguard.auth.model.LocalUser;
import com.circleguard.auth.repository.LocalUserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(MockitoExtension.class)
class UserControllerTest {

    @Mock
    private LocalUserRepository repository;

    @InjectMocks
    private UserController controller;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    @Test
    void getUsersByPermission_ReturnsUsernameAndEmail() throws Exception {
        LocalUser user = LocalUser.builder().username("nurse").email("nurse@example.com").build();
        when(repository.findUsersByPermissionName("alert:receive")).thenReturn(List.of(user));

        mockMvc.perform(get("/api/v1/users/permissions/alert:receive"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].username").value("nurse"))
                .andExpect(jsonPath("$[0].email").value("nurse@example.com"));
    }

    @Test
    void getUsersByPermission_UsesAnEmptyEmailWhenTheUserHasNone() throws Exception {
        LocalUser user = LocalUser.builder().username("guard").email(null).build();
        when(repository.findUsersByPermissionName("gate:open")).thenReturn(List.of(user));

        mockMvc.perform(get("/api/v1/users/permissions/gate:open"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].email").value(""));
    }

    @Test
    void getUsersByPermission_WithNoMatches_ReturnsAnEmptyList() throws Exception {
        when(repository.findUsersByPermissionName("nobody")).thenReturn(List.of());

        mockMvc.perform(get("/api/v1/users/permissions/nobody"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isEmpty());
    }
}
