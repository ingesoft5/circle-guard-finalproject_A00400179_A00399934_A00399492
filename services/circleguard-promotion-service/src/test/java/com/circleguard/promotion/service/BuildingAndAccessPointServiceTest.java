package com.circleguard.promotion.service;

import com.circleguard.promotion.model.AccessPoint;
import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.model.Floor;
import com.circleguard.promotion.repository.jpa.AccessPointRepository;
import com.circleguard.promotion.repository.jpa.BuildingRepository;
import com.circleguard.promotion.repository.jpa.FloorRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** BuildingService, AccessPointService and the branches of FloorService that FloorServiceTest does not reach. */
@ExtendWith(MockitoExtension.class)
class BuildingAndAccessPointServiceTest {

    @Mock
    private BuildingRepository buildingRepository;
    @Mock
    private FloorRepository floorRepository;
    @Mock
    private AccessPointRepository accessPointRepository;

    private final UUID id = UUID.randomUUID();

    // ---- BuildingService -------------------------------------------------------------------------

    @Test
    void buildingService_CreateStoresTheCoordinatesAndAddress() {
        BuildingService service = new BuildingService(buildingRepository, floorRepository);
        when(buildingRepository.save(any(Building.class))).thenAnswer(i -> i.getArgument(0));

        Building building = service.createBuilding("Lab", "LAB", "Labs", 3.4, -76.5, "Calle 1");

        assertThat(building.getLatitude()).isEqualTo(3.4);
        assertThat(building.getLongitude()).isEqualTo(-76.5);
        assertThat(building.getAddress()).isEqualTo("Calle 1");
    }

    @Test
    void buildingService_GetAllDelegates() {
        BuildingService service = new BuildingService(buildingRepository, floorRepository);
        List<Building> all = List.of(Building.builder().name("A").code("A").build());
        when(buildingRepository.findAll()).thenReturn(all);

        assertThat(service.getAllBuildings()).isSameAs(all);
    }

    @Test
    void buildingService_UpdateChangesEveryField() {
        BuildingService service = new BuildingService(buildingRepository, floorRepository);
        Building stored = Building.builder().id(id).name("o").code("o").build();
        when(buildingRepository.findById(id)).thenReturn(Optional.of(stored));
        when(buildingRepository.save(stored)).thenReturn(stored);

        Building updated = service.updateBuilding(id, "n", "c", "d", 1.0, 2.0, "addr");

        assertThat(updated.getName()).isEqualTo("n");
        assertThat(updated.getLatitude()).isEqualTo(1.0);
        assertThat(updated.getAddress()).isEqualTo("addr");
    }

    @Test
    void buildingService_UpdateUnknownThrows() {
        BuildingService service = new BuildingService(buildingRepository, floorRepository);
        when(buildingRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.updateBuilding(id, "n", "c", "d", 1.0, 2.0, "a"))
                .hasMessage("Building not found");
    }

    @Test
    void buildingService_DeleteIsRefusedWhileItHasFloors() {
        BuildingService service = new BuildingService(buildingRepository, floorRepository);
        when(floorRepository.findByBuildingId(id)).thenReturn(List.of(Floor.builder().build()));

        assertThatThrownBy(() -> service.deleteBuilding(id)).hasMessage("Cannot delete building with existing floors");
        verify(buildingRepository, never()).deleteById(any());
    }

    @Test
    void buildingService_DeleteWithoutFloorsDeletes() {
        BuildingService service = new BuildingService(buildingRepository, floorRepository);
        when(floorRepository.findByBuildingId(id)).thenReturn(List.of());

        service.deleteBuilding(id);

        verify(buildingRepository).deleteById(id);
    }

    // ---- FloorService ----------------------------------------------------------------------------

    @Test
    void floorService_AddFloorAndQueries() {
        FloorService service = new FloorService(buildingRepository, floorRepository, accessPointRepository);
        Building building = Building.builder().id(id).build();
        when(buildingRepository.findById(id)).thenReturn(Optional.of(building));
        when(floorRepository.save(any(Floor.class))).thenAnswer(i -> i.getArgument(0));
        when(floorRepository.findByBuildingId(id)).thenReturn(List.of());

        Floor floor = service.addFloor(id, 2, "Second");

        assertThat(floor.getBuilding()).isSameAs(building);
        assertThat(service.getFloorsByBuilding(id)).isEmpty();
    }

    @Test
    void floorService_AddFloorToAnUnknownBuildingThrows() {
        FloorService service = new FloorService(buildingRepository, floorRepository, accessPointRepository);
        when(buildingRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.addFloor(id, 1, "x")).hasMessage("Building not found");
    }

    @Test
    void floorService_UpdateChangesOnlyTheFieldsThatAreGiven() {
        FloorService service = new FloorService(buildingRepository, floorRepository, accessPointRepository);
        Floor stored = Floor.builder().id(id).floorNumber(1).name("One").floorPlanUrl("old.png").build();
        when(floorRepository.findById(id)).thenReturn(Optional.of(stored));
        when(floorRepository.save(stored)).thenReturn(stored);

        Floor updated = service.updateFloor(id, 5, null, null);

        assertThat(updated.getFloorNumber()).isEqualTo(5);
        assertThat(updated.getName()).isEqualTo("One");
        assertThat(updated.getFloorPlanUrl()).isEqualTo("old.png");
    }

    @Test
    void floorService_UpdateUnknownThrows() {
        FloorService service = new FloorService(buildingRepository, floorRepository, accessPointRepository);
        when(floorRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.updateFloor(id, 1, "n", "u")).hasMessage("Floor not found");
    }

    @Test
    void floorService_DeleteRules() {
        FloorService service = new FloorService(buildingRepository, floorRepository, accessPointRepository);
        when(accessPointRepository.findByFloorId(id)).thenReturn(List.of(AccessPoint.builder().build()));

        assertThatThrownBy(() -> service.deleteFloor(id)).hasMessage("Cannot delete floor with existing access points");

        when(accessPointRepository.findByFloorId(id)).thenReturn(List.of());
        service.deleteFloor(id);
        verify(floorRepository).deleteById(id);
    }

    // ---- AccessPointService ----------------------------------------------------------------------

    @Test
    void accessPointService_RegisterStoresPositionAndFloor() {
        AccessPointService service = new AccessPointService(accessPointRepository, floorRepository);
        Floor floor = Floor.builder().id(id).build();
        when(floorRepository.findById(id)).thenReturn(Optional.of(floor));
        when(accessPointRepository.save(any(AccessPoint.class))).thenAnswer(i -> i.getArgument(0));

        AccessPoint ap = service.registerAccessPoint(id, "aa:bb", 1.0, 2.0, "AP");

        assertThat(ap.getFloor()).isSameAs(floor);
        assertThat(ap.getName()).isEqualTo("AP");
    }

    @Test
    void accessPointService_RegisterOnAnUnknownFloorThrows() {
        AccessPointService service = new AccessPointService(accessPointRepository, floorRepository);
        when(floorRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.registerAccessPoint(id, "m", 0.0, 0.0, "n")).hasMessage("Floor not found");
    }

    @Test
    void accessPointService_QueriesAndDelete() {
        AccessPointService service = new AccessPointService(accessPointRepository, floorRepository);
        AccessPoint ap = AccessPoint.builder().id(id).build();
        when(accessPointRepository.findById(id)).thenReturn(Optional.of(ap));
        when(accessPointRepository.findByFloorId(id)).thenReturn(List.of(ap));

        assertThat(service.getAccessPoint(id)).contains(ap);
        assertThat(service.getAccessPointsByFloor(id)).containsExactly(ap);
        service.deleteAccessPoint(id);
        verify(accessPointRepository).deleteById(id);
    }

    @Test
    void accessPointService_UpdateChangesEveryFieldOrThrows() {
        AccessPointService service = new AccessPointService(accessPointRepository, floorRepository);
        AccessPoint stored = AccessPoint.builder().id(id).macAddress("old").coordinateX(0.0).coordinateY(0.0).name("old").build();
        when(accessPointRepository.findById(id)).thenReturn(Optional.of(stored));
        when(accessPointRepository.save(stored)).thenReturn(stored);

        AccessPoint updated = service.updateAccessPoint(id, "new", 7.0, 8.0, "renamed");

        assertThat(updated.getMacAddress()).isEqualTo("new");
        assertThat(updated.getCoordinateX()).isEqualTo(7.0);

        UUID other = UUID.randomUUID();
        when(accessPointRepository.findById(other)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.updateAccessPoint(other, "m", 0.0, 0.0, "n"))
                .hasMessage("Access Point not found");
    }
}
