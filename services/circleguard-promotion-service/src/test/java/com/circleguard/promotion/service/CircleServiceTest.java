package com.circleguard.promotion.service;

import com.circleguard.promotion.model.graph.CircleNode;
import com.circleguard.promotion.model.graph.UserNode;
import com.circleguard.promotion.repository.graph.CircleNodeRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CircleServiceTest {

    @Mock
    private CircleNodeRepository circleRepository;
    @Mock
    private HealthStatusService healthStatusService;

    @InjectMocks
    private CircleService service;

    private static UserNode user(String id, String status) {
        return UserNode.builder().anonymousId(id).status(status).build();
    }

    private static CircleNode circle(boolean valid, UserNode... members) {
        return CircleNode.builder().id(7L).name("Study group").isValid(valid).members(Set.of(members)).build();
    }

    @Test
    void toggleCircleValidity_Invalidating_ResolvesEveryMember() {
        CircleNode circle = circle(true, user("a", "SUSPECT"), user("b", "PROBABLE"));
        when(circleRepository.findById(7L)).thenReturn(Optional.of(circle));

        service.toggleCircleValidity(7L);

        assertThat(circle.getIsValid()).isFalse();
        verify(circleRepository).save(circle);
        verify(healthStatusService).resolveStatus("a");
        verify(healthStatusService).resolveStatus("b");
    }

    @Test
    void toggleCircleValidity_Revalidating_DoesNotResolveAnyone() {
        CircleNode circle = circle(false, user("a", "ACTIVE"));
        when(circleRepository.findById(7L)).thenReturn(Optional.of(circle));

        service.toggleCircleValidity(7L);

        assertThat(circle.getIsValid()).isTrue();
        verify(healthStatusService, never()).resolveStatus(anyString());
    }

    @Test
    void toggleCircleValidity_UnknownCircle_Throws() {
        when(circleRepository.findById(7L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.toggleCircleValidity(7L)).hasMessage("Circle not found");
    }

    @Test
    void forceFenceCircle_PromotesOnlyActiveMembersToProbable() {
        CircleNode circle = circle(true, user("active", "ACTIVE"), user("sick", "CONFIRMED"), user("risk", "SUSPECT"));
        when(circleRepository.findById(7L)).thenReturn(Optional.of(circle));

        service.forceFenceCircle(7L);

        assertThat(circle.getForceFence()).isTrue();
        verify(circleRepository).save(circle);
        verify(healthStatusService).updateStatus("active", "PROBABLE");
        verify(healthStatusService, never()).updateStatus("sick", "PROBABLE");
        verify(healthStatusService, never()).updateStatus("risk", "PROBABLE");
    }

    @Test
    void forceFenceCircle_UnknownCircle_Throws() {
        when(circleRepository.findById(7L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.forceFenceCircle(7L)).hasMessage("Circle not found");
    }

    @Test
    void createCircle_GeneratesAMeshInviteCodeAndSavesTheCircle() {
        when(circleRepository.existsByInviteCode(anyString())).thenReturn(false);
        when(circleRepository.save(any(CircleNode.class))).thenAnswer(i -> i.getArgument(0));

        CircleNode created = service.createCircle("Lab team", "lab-1");

        assertThat(created.getName()).isEqualTo("Lab team");
        assertThat(created.getLocationId()).isEqualTo("lab-1");
        assertThat(created.getIsActive()).isTrue();
        assertThat(created.getInviteCode()).matches("MESH-[A-HJ-NP-Z2-9]{4}");
    }

    @Test
    void createCircle_RetriesWhileTheInviteCodeIsTaken() {
        when(circleRepository.existsByInviteCode(anyString())).thenReturn(true, true, false);
        when(circleRepository.save(any(CircleNode.class))).thenAnswer(i -> i.getArgument(0));

        service.createCircle("Lab team", "lab-1");

        ArgumentCaptor<String> codes = ArgumentCaptor.forClass(String.class);
        verify(circleRepository, org.mockito.Mockito.times(3)).existsByInviteCode(codes.capture());
        assertThat(codes.getAllValues()).hasSize(3);
    }

    @Test
    void joinCircle_ReturnsTheCircleOfTheInviteCode() {
        CircleNode circle = circle(true);
        when(circleRepository.joinCircle("a", "MESH-ABCD")).thenReturn(Optional.of(circle));

        assertThat(service.joinCircle("a", "MESH-ABCD")).isSameAs(circle);
    }

    @Test
    void joinCircle_InvalidCode_Throws() {
        when(circleRepository.joinCircle("a", "bad")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.joinCircle("a", "bad"))
                .hasMessage("Invalid invite code or user already member");
    }

    @Test
    void addMember_AddsTheUserOrFails() {
        CircleNode circle = circle(true);
        when(circleRepository.addUserToCircle("a", 7L)).thenReturn(Optional.of(circle));
        when(circleRepository.addUserToCircle("ghost", 7L)).thenReturn(Optional.empty());

        assertThat(service.addMember(7L, "a")).isSameAs(circle);
        assertThatThrownBy(() -> service.addMember(7L, "ghost")).hasMessage("Failed to add user to circle");
    }

    @Test
    void getUserCircles_DelegatesToTheRepository() {
        List<CircleNode> circles = List.of(circle(true));
        when(circleRepository.findCirclesByUser("a")).thenReturn(circles);

        assertThat(service.getUserCircles("a")).isSameAs(circles);
    }
}
