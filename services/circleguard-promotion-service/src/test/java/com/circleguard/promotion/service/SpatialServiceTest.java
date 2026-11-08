package com.circleguard.promotion.service;

import com.circleguard.promotion.model.AccessPoint;
import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.model.Floor;
import com.circleguard.promotion.repository.jpa.AccessPointRepository;
import com.circleguard.promotion.repository.jpa.BuildingRepository;
import com.circleguard.promotion.repository.jpa.FloorRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
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

@ExtendWith(MockitoExtension.class)
class SpatialServiceTest {

    @Mock
    private BuildingRepository buildingRepository;
    @Mock
    private FloorRepository floorRepository;
    @Mock
    private AccessPointRepository accessPointRepository;

    @InjectMocks
    private SpatialService service;

    private final UUID id = UUID.randomUUID();

    @Test
    void createBuilding_SavesTheGivenData() {
        when(buildingRepository.save(any(Building.class))).thenAnswer(i -> i.getArgument(0));

        Building building = service.createBuilding("Main", "MAIN", "Main building");

        assertThat(building.getName()).isEqualTo("Main");
        assertThat(building.getCode()).isEqualTo("MAIN");
        assertThat(building.getDescription()).isEqualTo("Main building");
    }

    @Test
    void addFloor_LinksTheFloorToItsBuilding() {
        Building building = Building.builder().id(id).name("Main").code("M").build();
        when(buildingRepository.findById(id)).thenReturn(Optional.of(building));
        when(floorRepository.save(any(Floor.class))).thenAnswer(i -> i.getArgument(0));

        Floor floor = service.addFloor(id, 3, "Third");

        assertThat(floor.getBuilding()).isSameAs(building);
        assertThat(floor.getFloorNumber()).isEqualTo(3);
        assertThat(floor.getName()).isEqualTo("Third");
    }

    @Test
    void addFloor_UnknownBuilding_Throws() {
        when(buildingRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.addFloor(id, 1, "x")).hasMessage("Building not found");
        verify(floorRepository, never()).save(any());
    }

    @Test
    void getAllBuildings_AndFloorsByBuilding_DelegateToTheRepositories() {
        List<Building> buildings = List.of(Building.builder().name("A").code("A").build());
        List<Floor> floors = List.of(Floor.builder().floorNumber(1).build());
        when(buildingRepository.findAll()).thenReturn(buildings);
        when(floorRepository.findByBuildingId(id)).thenReturn(floors);

        assertThat(service.getAllBuildings()).isSameAs(buildings);
        assertThat(service.getFloorsByBuilding(id)).isSameAs(floors);
    }

    @Test
    void updateBuilding_ChangesNameCodeAndDescription() {
        Building stored = Building.builder().id(id).name("Old").code("O").description("old").build();
        when(buildingRepository.findById(id)).thenReturn(Optional.of(stored));
        when(buildingRepository.save(stored)).thenReturn(stored);

        Building updated = service.updateBuilding(id, "New", "N", "new");

        assertThat(updated.getName()).isEqualTo("New");
        assertThat(updated.getCode()).isEqualTo("N");
        assertThat(updated.getDescription()).isEqualTo("new");
    }

    @Test
    void updateBuilding_UnknownId_Throws() {
        when(buildingRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.updateBuilding(id, "n", "c", "d")).hasMessage("Building not found");
    }

    @Test
    void deleteBuilding_WithoutFloors_Deletes() {
        when(floorRepository.findByBuildingId(id)).thenReturn(List.of());

        service.deleteBuilding(id);

        verify(buildingRepository).deleteById(id);
    }

    @Test
    void deleteBuilding_WithFloors_IsRefused() {
        when(floorRepository.findByBuildingId(id)).thenReturn(List.of(Floor.builder().build()));

        assertThatThrownBy(() -> service.deleteBuilding(id)).hasMessage("Cannot delete building with existing floors");
        verify(buildingRepository, never()).deleteById(any());
    }

    @Test
    void updateFloor_ChangesNumberAndName() {
        Floor stored = Floor.builder().id(id).floorNumber(1).name("One").build();
        when(floorRepository.findById(id)).thenReturn(Optional.of(stored));
        when(floorRepository.save(stored)).thenReturn(stored);

        Floor updated = service.updateFloor(id, 2, "Two");

        assertThat(updated.getFloorNumber()).isEqualTo(2);
        assertThat(updated.getName()).isEqualTo("Two");
    }

    @Test
    void updateFloor_UnknownId_Throws() {
        when(floorRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.updateFloor(id, 1, "x")).hasMessage("Floor not found");
    }

    @Test
    void deleteFloor_WithAccessPoints_IsRefused() {
        when(accessPointRepository.findByFloorId(id)).thenReturn(List.of(AccessPoint.builder().build()));

        assertThatThrownBy(() -> service.deleteFloor(id)).hasMessage("Cannot delete floor with existing access points");
        verify(floorRepository, never()).deleteById(any());
    }

    @Test
    void deleteFloor_WithoutAccessPoints_Deletes() {
        when(accessPointRepository.findByFloorId(id)).thenReturn(List.of());

        service.deleteFloor(id);

        verify(floorRepository).deleteById(id);
    }

    @Test
    void registerAccessPoint_StoresPositionAndFloor() {
        Floor floor = Floor.builder().id(id).floorNumber(1).build();
        when(floorRepository.findById(id)).thenReturn(Optional.of(floor));
        when(accessPointRepository.save(any(AccessPoint.class))).thenAnswer(i -> i.getArgument(0));

        AccessPoint ap = service.registerAccessPoint(id, "aa:bb:cc:dd:ee:ff", 1.5, 2.5, "AP-1");

        assertThat(ap.getFloor()).isSameAs(floor);
        assertThat(ap.getMacAddress()).isEqualTo("aa:bb:cc:dd:ee:ff");
        assertThat(ap.getCoordinateX()).isEqualTo(1.5);
        assertThat(ap.getCoordinateY()).isEqualTo(2.5);
    }

    @Test
    void registerAccessPoint_UnknownFloor_Throws() {
        when(floorRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.registerAccessPoint(id, "m", 0.0, 0.0, "n")).hasMessage("Floor not found");
    }

    @Test
    void accessPointQueries_DelegateToTheRepository() {
        AccessPoint ap = AccessPoint.builder().id(id).build();
        when(accessPointRepository.findById(id)).thenReturn(Optional.of(ap));
        when(accessPointRepository.findByFloorId(id)).thenReturn(List.of(ap));

        assertThat(service.getAccessPoint(id)).contains(ap);
        assertThat(service.getAccessPointsByFloor(id)).containsExactly(ap);
    }

    @Test
    void updateAccessPoint_ChangesEveryField() {
        AccessPoint stored = AccessPoint.builder().id(id).macAddress("old").coordinateX(0.0).coordinateY(0.0).name("old").build();
        when(accessPointRepository.findById(id)).thenReturn(Optional.of(stored));
        when(accessPointRepository.save(stored)).thenReturn(stored);

        AccessPoint updated = service.updateAccessPoint(id, "new", 3.0, 4.0, "new");

        assertThat(updated.getMacAddress()).isEqualTo("new");
        assertThat(updated.getCoordinateX()).isEqualTo(3.0);
        assertThat(updated.getCoordinateY()).isEqualTo(4.0);
        assertThat(updated.getName()).isEqualTo("new");
    }

    @Test
    void updateAccessPoint_UnknownId_Throws() {
        when(accessPointRepository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.updateAccessPoint(id, "m", 0.0, 0.0, "n")).hasMessage("Access Point not found");
    }

    @Test
    void deleteAccessPoint_DeletesById() {
        service.deleteAccessPoint(id);

        verify(accessPointRepository).deleteById(id);
    }
}
