!=================================================================================================================================
! Copyright (c) 2010-2019  Prof. Claus-Dieter Munz
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://nrg.iag.uni-stuttgart.de/
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
#include "flexi.h"
#include "particle.h"

!===================================================================================================================================
! module for MPI communication during particle emission
!===================================================================================================================================
MODULE MOD_Particle_MPI_Emission
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

#if USE_MPI
INTERFACE InitEmissionComm
  MODULE PROCEDURE InitEmissionComm
END INTERFACE

!INTERFACE InitEmissionParticlesToProcs
!  MODULE PROCEDURE InitEmissionParticlesToProcs
!END INTERFACE

INTERFACE SendEmissionParticlesToProcs
  MODULE PROCEDURE SendEmissionParticlesToProcs
END INTERFACE

!INTERFACE FinalizeEmissionParticlesToProcs
!  MODULE PROCEDURE FinalizeEmissionParticlesToProcs
!END INTERFACE

INTERFACE FinalizeEmissionComm
  MODULE PROCEDURE FinalizeEmissionComm
END INTERFACE


!PUBLIC :: InitEmissionParticlesToProcs
PUBLIC :: InitEmissionComm
PUBLIC :: SendEmissionParticlesToProcs
!PUBLIC :: FinalizeEmissionParticlesToProcs
PUBLIC :: FinalizeEmissionComm
!===================================================================================================================================
CONTAINS


SUBROUTINE InitEmissionComm()
!===================================================================================================================================
! build emission communicators for particle emission regions
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Particle_MPI_Vars,      ONLY:PartMPI
USE MOD_Particle_Vars,          ONLY:Species,nSpecies
USE MOD_Particle_Mesh_Vars,     ONLY:GEO
USE MOD_Particle_MPI_Vars,      ONLY:halo_eps
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: iSpec,iInit,iNode,iRank
INTEGER                         :: nInitRegions
LOGICAL                         :: RegionOnProc
REAL                            :: xCoords(3,8),lineVector(3),radius,height
REAL                            :: xlen,ylen,zlen
INTEGER                         :: color,iProc
INTEGER                         :: noInitRank,InitRank
LOGICAL                         :: hasRegion
!===================================================================================================================================

! get number of total init regions
nInitRegions=0
DO iSpec=1,nSpecies
  nInitRegions=nInitRegions+Species(iSpec)%NumberOfInits+(1-Species(iSpec)%StartnumberOfInits)
END DO ! iSpec
IF(nInitRegions.EQ.0) RETURN

! allocate communicators
ALLOCATE( PartMPI%InitGroup(1:nInitRegions))

nInitRegions=0
DO iSpec=1,nSpecies
  RegionOnProc=.FALSE.
  DO iInit=Species(iSpec)%StartnumberOfInits, Species(iSpec)%NumberOfInits
    nInitRegions=nInitRegions+1
    SELECT CASE(TRIM(Species(iSpec)%Init(iInit)%SpaceIC))
    CASE ('point')
       xCoords(1:3,1)=Species(iSpec)%Init(iInit)%BasePointIC
       RegionOnProc=PointInProc(xCoords(1:3,1))
    CASE ('line_with_equidistant_distribution')
      xCoords(1:3,1)=Species(iSpec)%Init(iInit)%BasePointIC
      xCoords(1:3,2)=Species(iSpec)%Init(iInit)%BasePointIC+Species(iSpec)%Init(iInit)%BaseVector1IC
      RegionOnProc=BoxInProc(xCoords(1:3,1:2),2)
    CASE ('line')
      xCoords(1:3,1)=Species(iSpec)%Init(iInit)%BasePointIC
      xCoords(1:3,2)=Species(iSpec)%Init(iInit)%BasePointIC+Species(iSpec)%Init(iInit)%BaseVector1IC
      RegionOnProc=BoxInProc(xCoords(1:3,1:2),2)
    CASE ('Gaussian')
      xlen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(1)*Species(iSpec)%Init(iInit)%NormalIC(1))
      ylen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(2)*Species(iSpec)%Init(iInit)%NormalIC(2))
      zlen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(3)*Species(iSpec)%Init(iInit)%NormalIC(3))
      ! all 8 edges
      xCoords(1:3,1) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,-ylen,-zlen/)
      xCoords(1:3,2) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,-ylen,-zlen/)
      xCoords(1:3,3) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,+ylen,-zlen/)
      xCoords(1:3,4) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,+ylen,-zlen/)
      xCoords(1:3,5) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,-ylen,+zlen/)
      xCoords(1:3,6) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,-ylen,+zlen/)
      xCoords(1:3,7) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,+ylen,+zlen/)
      xCoords(1:3,8) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,+ylen,+zlen/)
      RegionOnProc=BoxInProc(xCoords(1:3,1:8),8)
    CASE('disc')
      xlen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(1)*Species(iSpec)%Init(iInit)%NormalIC(1))
      ylen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(2)*Species(iSpec)%Init(iInit)%NormalIC(2))
      zlen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(3)*Species(iSpec)%Init(iInit)%NormalIC(3))
      ! all 8 edges
      xCoords(1:3,1) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,-ylen,-zlen/)
      xCoords(1:3,2) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,-ylen,-zlen/)
      xCoords(1:3,3) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,+ylen,-zlen/)
      xCoords(1:3,4) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,+ylen,-zlen/)
      xCoords(1:3,5) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,-ylen,+zlen/)
      xCoords(1:3,6) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,-ylen,+zlen/)
      xCoords(1:3,7) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,+ylen,+zlen/)
      xCoords(1:3,8) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,+ylen,+zlen/)
      RegionOnProc=BoxInProc(xCoords(1:3,1:8),8)
    CASE('circle')
      xlen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(1)*Species(iSpec)%Init(iInit)%NormalIC(1))
      ylen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(2)*Species(iSpec)%Init(iInit)%NormalIC(2))
      zlen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(3)*Species(iSpec)%Init(iInit)%NormalIC(3))
      ! all 8 edges
      xCoords(1:3,1) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,-ylen,-zlen/)
      xCoords(1:3,2) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,-ylen,-zlen/)
      xCoords(1:3,3) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,+ylen,-zlen/)
      xCoords(1:3,4) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,+ylen,-zlen/)
      xCoords(1:3,5) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,-ylen,+zlen/)
      xCoords(1:3,6) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,-ylen,+zlen/)
      xCoords(1:3,7) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,+ylen,+zlen/)
      xCoords(1:3,8) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,+ylen,+zlen/)
      RegionOnProc=BoxInProc(xCoords(1:3,1:8),8)
    CASE('circle_equidistant')
      xlen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(1)*Species(iSpec)%Init(iInit)%NormalIC(1))
      ylen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(2)*Species(iSpec)%Init(iInit)%NormalIC(2))
      zlen=Species(iSpec)%Init(iInit)%RadiusIC * &
           SQRT(1.0 - Species(iSpec)%Init(iInit)%NormalIC(3)*Species(iSpec)%Init(iInit)%NormalIC(3))
      ! all 8 edges
      xCoords(1:3,1) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,-ylen,-zlen/)
      xCoords(1:3,2) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,-ylen,-zlen/)
      xCoords(1:3,3) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,+ylen,-zlen/)
      xCoords(1:3,4) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,+ylen,-zlen/)
      xCoords(1:3,5) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,-ylen,+zlen/)
      xCoords(1:3,6) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,-ylen,+zlen/)
      xCoords(1:3,7) = Species(iSpec)%Init(iInit)%BasePointIC+(/-xlen,+ylen,+zlen/)
      xCoords(1:3,8) = Species(iSpec)%Init(iInit)%BasePointIC+(/+xlen,+ylen,+zlen/)
      RegionOnProc=BoxInProc(xCoords(1:3,1:8),8)
    CASE('cuboid')
      lineVector(1) = Species(iSpec)%Init(iInit)%BaseVector1IC(2) * Species(iSpec)%Init(iInit)%BaseVector2IC(3) - &
        Species(iSpec)%Init(iInit)%BaseVector1IC(3) * Species(iSpec)%Init(iInit)%BaseVector2IC(2)
      lineVector(2) = Species(iSpec)%Init(iInit)%BaseVector1IC(3) * Species(iSpec)%Init(iInit)%BaseVector2IC(1) - &
        Species(iSpec)%Init(iInit)%BaseVector1IC(1) * Species(iSpec)%Init(iInit)%BaseVector2IC(3)
      lineVector(3) = Species(iSpec)%Init(iInit)%BaseVector1IC(1) * Species(iSpec)%Init(iInit)%BaseVector2IC(2) - &
        Species(iSpec)%Init(iInit)%BaseVector1IC(2) * Species(iSpec)%Init(iInit)%BaseVector2IC(1)
      IF ((lineVector(1).eq.0).AND.(lineVector(2).eq.0).AND.(lineVector(3).eq.0)) THEN
         CALL ABORT(&
         __STAMP__&
         ,'BaseVectors are parallel!')
      ELSE
        lineVector = lineVector / SQRT(lineVector(1) * lineVector(1) + lineVector(2) * lineVector(2) + &
          lineVector(3) * lineVector(3))
      END IF
      xCoords(1:3,1)=Species(iSpec)%Init(iInit)%BasePointIC
      xCoords(1:3,2)=Species(iSpec)%Init(iInit)%BasePointIC+Species(iSpec)%Init(iInit)%BaseVector1IC
      xCoords(1:3,3)=Species(iSpec)%Init(iInit)%BasePointIC+Species(iSpec)%Init(iInit)%BaseVector2IC
      xCoords(1:3,4)=Species(iSpec)%Init(iInit)%BasePointIC+Species(iSpec)%Init(iInit)%BaseVector1IC&
                                                           +Species(iSpec)%Init(iInit)%BaseVector2IC

      IF (Species(iSpec)%Init(iInit)%CalcHeightFromDt) THEN !directly calculated by timestep
        height = halo_eps
      ELSE
        height= Species(iSpec)%Init(iInit)%CuboidHeightIC
      END IF
      DO iNode=1,4
        xCoords(1:3,iNode+4)=xCoords(1:3,iNode)+lineVector*height
      END DO ! iNode
      RegionOnProc=BoxInProc(xCoords,8)
    CASE('cylinder')
      lineVector(1) = Species(iSpec)%Init(iInit)%BaseVector1IC(2) * Species(iSpec)%Init(iInit)%BaseVector2IC(3) - &
        Species(iSpec)%Init(iInit)%BaseVector1IC(3) * Species(iSpec)%Init(iInit)%BaseVector2IC(2)
      lineVector(2) = Species(iSpec)%Init(iInit)%BaseVector1IC(3) * Species(iSpec)%Init(iInit)%BaseVector2IC(1) - &
        Species(iSpec)%Init(iInit)%BaseVector1IC(1) * Species(iSpec)%Init(iInit)%BaseVector2IC(3)
      lineVector(3) = Species(iSpec)%Init(iInit)%BaseVector1IC(1) * Species(iSpec)%Init(iInit)%BaseVector2IC(2) - &
        Species(iSpec)%Init(iInit)%BaseVector1IC(2) * Species(iSpec)%Init(iInit)%BaseVector2IC(1)
      IF ((lineVector(1).eq.0).AND.(lineVector(2).eq.0).AND.(lineVector(3).eq.0)) THEN
         CALL ABORT(&
         __STAMP__&
         ,'BaseVectors are parallel!')
      ELSE
        lineVector = lineVector / SQRT(lineVector(1) * lineVector(1) + lineVector(2) * lineVector(2) + &
          lineVector(3) * lineVector(3))
      END IF
      radius = Species(iSpec)%Init(iInit)%RadiusIC
      ! here no radius, already inclueded
      xCoords(1:3,1)=Species(iSpec)%Init(iInit)%BasePointIC-Species(iSpec)%Init(iInit)%BaseVector1IC &
                                                           -Species(iSpec)%Init(iInit)%BaseVector2IC

      xCoords(1:3,2)=xCoords(1:3,1)+2.0*Species(iSpec)%Init(iInit)%BaseVector1IC
      xCoords(1:3,3)=xCoords(1:3,1)+2.0*Species(iSpec)%Init(iInit)%BaseVector2IC
      xCoords(1:3,4)=xCoords(1:3,1)+2.0*Species(iSpec)%Init(iInit)%BaseVector1IC&
                                   +2.0*Species(iSpec)%Init(iInit)%BaseVector2IC

      IF (Species(iSpec)%Init(iInit)%CalcHeightFromDt) THEN !directly calculated by timestep
        height = halo_eps
      ELSE
        height= Species(iSpec)%Init(iInit)%CylinderHeightIC
      END IF
      DO iNode=1,4
        xCoords(1:3,iNode+4)=xCoords(1:3,iNode)+lineVector*height
      END DO ! iNode
      RegionOnProc=BoxInProc(xCoords,8)
    CASE('cuboid_equal')
       xlen = SQRT(Species(iSpec)%Init(iInit)%BaseVector1IC(1)**2 &
            + Species(iSpec)%Init(iInit)%BaseVector1IC(2)**2 &
            + Species(iSpec)%Init(iInit)%BaseVector1IC(3)**2 )
       ylen = SQRT(Species(iSpec)%Init(iInit)%BaseVector2IC(1)**2 &
            + Species(iSpec)%Init(iInit)%BaseVector2IC(2)**2 &
            + Species(iSpec)%Init(iInit)%BaseVector2IC(3)**2 )
       zlen = ABS(Species(iSpec)%Init(iInit)%CuboidHeightIC)

       ! make sure the vectors correspond to x,y,z-dir
       IF ((xlen.NE.Species(iSpec)%Init(iInit)%BaseVector1IC(1)).OR. &
           (ylen.NE.Species(iSpec)%Init(iInit)%BaseVector2IC(2)).OR. &
           (zlen.NE.Species(iSpec)%Init(iInit)%CuboidHeightIC)) THEN
          CALL ABORT(&
          __STAMP__&
          ,'Basevectors1IC,-2IC and CuboidHeightIC have to be in x,y,z-direction, respectively for emission condition')
       END IF
       DO iNode=1,8
        xCoords(1:3,iNode) = Species(iSpec)%Init(iInit)%BasePointIC(1:3)
       END DO
       xCoords(1:3,2) = xCoords(1:3,1) + (/xlen,0.,0./)
       xCoords(1:3,3) = xCoords(1:3,1) + (/0.,ylen,0./)
       xCoords(1:3,4) = xCoords(1:3,1) + (/xlen,ylen,0./)
       xCoords(1:3,5) = xCoords(1:3,1) + (/0.,0.,zlen/)
       xCoords(1:3,6) = xCoords(1:3,5) + (/xlen,0.,0./)
       xCoords(1:3,7) = xCoords(1:3,5) + (/0.,ylen,0./)
       xCoords(1:3,8) = xCoords(1:3,5) + (/xlen,ylen,0./)
       RegionOnProc=BoxInProc(xCoords,8)

     !~j CALL ABORT(&
     !~j __STAMP__&
     !~j ,'ERROR in ParticleEmission_parallel: cannot deallocate particle_positions!')
    CASE ('cuboid_with_equidistant_distribution')
       xlen = SQRT(Species(iSpec)%Init(iInit)%BaseVector1IC(1)**2 &
            + Species(iSpec)%Init(iInit)%BaseVector1IC(2)**2 &
            + Species(iSpec)%Init(iInit)%BaseVector1IC(3)**2 )
       ylen = SQRT(Species(iSpec)%Init(iInit)%BaseVector2IC(1)**2 &
            + Species(iSpec)%Init(iInit)%BaseVector2IC(2)**2 &
            + Species(iSpec)%Init(iInit)%BaseVector2IC(3)**2 )
       zlen = ABS(Species(iSpec)%Init(iInit)%CuboidHeightIC)

       ! make sure the vectors correspond to x,y,z-dir
       IF ((xlen.NE.Species(iSpec)%Init(iInit)%BaseVector1IC(1)).OR. &
           (ylen.NE.Species(iSpec)%Init(iInit)%BaseVector2IC(2)).OR. &
           (zlen.NE.Species(iSpec)%Init(iInit)%CuboidHeightIC)) THEN
          CALL ABORT(&
          __STAMP__&
          ,'Basevectors1IC,-2IC and CuboidHeightIC have to be in x,y,z-direction, respectively for emission condition')
       END IF
       DO iNode=1,8
        xCoords(1:3,iNode) = Species(iSpec)%Init(iInit)%BasePointIC(1:3)
       END DO
       xCoords(1:3,2) = xCoords(1:3,1) + (/xlen,0.,0./)
       xCoords(1:3,3) = xCoords(1:3,1) + (/0.,ylen,0./)
       xCoords(1:3,4) = xCoords(1:3,1) + (/xlen,ylen,0./)
       xCoords(1:3,5) = xCoords(1:3,1) + (/0.,0.,zlen/)
       xCoords(1:3,6) = xCoords(1:3,5) + (/xlen,0.,0./)
       xCoords(1:3,7) = xCoords(1:3,5) + (/0.,ylen,0./)
       xCoords(1:3,8) = xCoords(1:3,5) + (/xlen,ylen,0./)
       RegionOnProc=BoxInProc(xCoords,8)
    CASE('sin_deviation')
       IF(Species(iSpec)%Init(iInit)%initialParticleNumber.NE. &
            (Species(iSpec)%Init(iInit)%maxParticleNumberX * Species(iSpec)%Init(iInit)%maxParticleNumberY &
            * Species(iSpec)%Init(iInit)%maxParticleNumberZ)) THEN
         SWRITE(*,*) 'for species ',iSpec,' does not match number of particles in each direction!'
         CALL ABORT(&
         __STAMP__&
         ,'ERROR: Number of particles in init / emission region',iInit)
       END IF
       xlen = abs(GEO%xmaxglob  - GEO%xminglob)
       ylen = abs(GEO%ymaxglob  - GEO%yminglob)
       zlen = abs(GEO%zmaxglob  - GEO%zminglob)
       xCoords(1:3,1) = (/GEO%xminglob,GEO%yminglob,GEO%zminglob/)
       xCoords(1:3,2) = xCoords(1:3,1) + (/xlen,0.,0./)
       xCoords(1:3,3) = xCoords(1:3,1) + (/0.,ylen,0./)
       xCoords(1:3,4) = xCoords(1:3,1) + (/xlen,ylen,0./)
       xCoords(1:3,5) = xCoords(1:3,1) + (/0.,0.,zlen/)
       xCoords(1:3,6) = xCoords(1:3,5) + (/xlen,0.,0./)
       xCoords(1:3,7) = xCoords(1:3,5) + (/0.,ylen,0./)
       xCoords(1:3,8) = xCoords(1:3,5) + (/xlen,ylen,0./)
       RegionOnProc=BoxInProc(xCoords,8)
    CASE DEFAULT
      CALL ABORT(&
      __STAMP__&
      ,'ERROR: Given SpaceIC is not implemented!')
    END SELECT
    ! create new communicator
    color=MPI_UNDEFINED
    IF(RegionOnProc) color=nInitRegions!+1
    ! set communicator id
    Species(iSpec)%Init(iInit)%InitComm=nInitRegions

    ! create ranks for RP communicator
    IF(PartMPI%MPIRoot) THEN
      InitRank=-1
      noInitRank=-1
      iRank=0
      PartMPI%InitGroup(nInitRegions)%MyRank=0
      IF(RegionOnProc) THEN
        InitRank=0
      ELSE
        noInitRank=0
      END IF
      DO iProc=1,PartMPI%nProcs-1
        CALL MPI_RECV(hasRegion,1,MPI_LOGICAL,iProc,0,PartMPI%COMM,MPIstatus,iError)
        IF(hasRegion) THEN
          InitRank=InitRank+1
          CALL MPI_SEND(InitRank,1,MPI_INTEGER,iProc,0,PartMPI%COMM,iError)
        ELSE
          noInitRank=noInitRank+1
          CALL MPI_SEND(noInitRank,1,MPI_INTEGER,iProc,0,PartMPI%COMM,iError)
        END IF
      END DO
    ELSE
      CALL MPI_SEND(RegionOnProc,1,MPI_LOGICAL,0,0,PartMPI%COMM,iError)
      CALL MPI_RECV(PartMPI%InitGroup(nInitRegions)%MyRank,1,MPI_INTEGER,0,0,PartMPI%COMM,MPIstatus,iError)
    END IF

    ! create new emission communicator
    CALL MPI_COMM_SPLIT(PartMPI%COMM, color, PartMPI%InitGroup(nInitRegions)%MyRank, PartMPI%InitGroup(nInitRegions)%COMM,iError)
    IF(RegionOnProc) CALL MPI_COMM_SIZE(PartMPI%InitGroup(nInitRegions)%COMM,PartMPI%InitGroup(nInitRegions)%nProcs ,iError)
    IF(PartMPI%InitGroup(nInitRegions)%MyRank.EQ.0 .AND. RegionOnProc) &
    WRITE(UNIT_StdOut,*) 'Emission-Region,Emission-Communicator:',nInitRegions,PartMPI%InitGroup(nInitRegions)%nProcs,' procs'
    IF(PartMPI%InitGroup(nInitRegions)%COMM.NE.MPI_COMM_NULL) THEN
      IF(PartMPI%InitGroup(nInitRegions)%MyRank.EQ.0) THEN
        PartMPI%InitGroup(nInitRegions)%MPIRoot=.TRUE.
      ELSE
        PartMPI%InitGroup(nInitRegions)%MPIRoot=.FALSE.
      END IF
      ALLOCATE(PartMPI%InitGroup(nInitRegions)%GroupToComm(0:PartMPI%InitGroup(nInitRegions)%nProcs-1))
      PartMPI%InitGroup(nInitRegions)%GroupToComm(PartMPI%InitGroup(nInitRegions)%MyRank)= PartMPI%MyRank
      CALL MPI_ALLGATHER(PartMPI%MyRank,1,MPI_INTEGER&
                        ,PartMPI%InitGroup(nInitRegions)%GroupToComm(0:PartMPI%InitGroup(nInitRegions)%nProcs-1)&
                       ,1,MPI_INTEGER,PartMPI%InitGroup(nInitRegions)%COMM,iERROR)
      ALLOCATE(PartMPI%InitGroup(nInitRegions)%CommToGroup(0:PartMPI%nProcs-1))
      PartMPI%InitGroup(nInitRegions)%CommToGroup(0:PartMPI%nProcs-1)=-1
      DO iRank=0,PartMPI%InitGroup(nInitRegions)%nProcs-1
        PartMPI%InitGroup(nInitRegions)%CommToGroup(PartMPI%InitGroup(nInitRegions)%GroupToComm(iRank))=iRank
      END DO ! iRank
    END IF
  END DO ! iniT
END DO ! iSpec

END SUBROUTINE InitEmissionComm


!SUBROUTINE InitEmissionParticlesToProcs()
!!----------------------------------------------------------------------------------------------------------------------------------!
!! Initializes the MPI communication during particle emission
!!----------------------------------------------------------------------------------------------------------------------------------!
!! MODULES                                                                                                                          !
!!----------------------------------------------------------------------------------------------------------------------------------!
!USE MOD_Globals
!USE MOD_Particle_MPI_Vars      ,ONLY: PartMPI,PartMPIInsert,PartMPILocate
!USE MOD_Particle_MPI_Vars      ,ONLY: EmissionSendBuf,EmissionRecvBuf
!USE MOD_Particle_Vars          ,ONLY: Species,nSpecies
!!----------------------------------------------------------------------------------------------------------------------------------!
!IMPLICIT NONE
!! INPUT / OUTPUT VARIABLES
!!-----------------------------------------------------------------------------------------------------------------------------------
!! LOCAL VARIABLES
!INTEGER                       :: i,iInit,InitGroup
!INTEGER                       :: ALLOCSTAT
!!===================================================================================================================================
!DO i = 1,nSpecies
!  DO iInit = 1, Species(i)%NumberOfInits
!    InitGroup = Species(i)%Init(iInit)%InitCOMM
!
!    ! Arrays for communication of particles not located in final element
!    ALLOCATE( PartMPIInsert%nPartsSend  (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , PartMPIInsert%nPartsRecv  (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , PartMPIInsert%SendRequest (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , PartMPIInsert%RecvRequest (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , PartMPIInsert%send_message(  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , STAT=ALLOCSTAT)
!    IF (ALLOCSTAT.NE.0) &
!      CALL ABORT(__STAMP__,' Cannot allocate particle emission MPI arrays! ALLOCSTAT',ALLOCSTAT)
!
!    ALLOCATE( PartMPILocate%nPartsSend (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , PartMPILocate%nPartsRecv (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , PartMPILocate%SendRequest(2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , PartMPILocate%RecvRequest(2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , EmissionRecvBuf          (  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , EmissionSendBuf          (  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
!            , STAT=ALLOCSTAT)
!    IF (ALLOCSTAT.NE.0) &
!      CALL ABORT(__STAMP__,' Cannot allocate particle emission MPI arrays! ALLOCSTAT',ALLOCSTAT)
!  END DO
!END DO
!
!END SUBROUTINE InitEmissionParticlesToProcs


SUBROUTINE SendEmissionParticlesToProcs(chunkSize,DimSend,FractNbr,iInit,mySumOfMatchedParticles,particle_positions)
!----------------------------------------------------------------------------------------------------------------------------------!
! A particle's host cell in the FIBGM is found and the corresponding procs are notified.
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Eval_xyz               ,ONLY: GetPositionInRefElem
USE MOD_Particle_Localization  ,ONLY: LocateParticleInElement,SinglePointToElement
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemInfo_Shared,ElemToProcID_Shared
!USE MOD_Particle_Mesh_Tools    ,ONLY: GetCNElemID
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_nElems, FIBGM_offsetElem, FIBGM_Element
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPI,PartMPIInsert,PartMPILocate
USE MOD_Particle_MPI_Vars      ,ONLY: EmissionSendBuf,EmissionRecvBuf
USE MOD_Particle_Vars          ,ONLY: PDM,PEM,PartState,PartPosRef,Species
USE MOD_Particle_Tracking_Vars ,ONLY: DoRefMapping
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT VARIABLES
INTEGER,INTENT(IN)            :: chunkSize
INTEGER,INTENT(IN)            :: DimSend
INTEGER,INTENT(IN)            :: FractNbr
INTEGER,INTENT(IN)            :: iInit
REAL,INTENT(IN),OPTIONAL      :: particle_positions(1:chunkSize*DimSend)
! OUTPUT VARIABLES
INTEGER,INTENT(OUT)           :: mySumOfMatchedParticles
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
! Counters
INTEGER                       :: i,iPos,iProc,iDir,ElemID,ProcID
! BGM
INTEGER                       :: ijkBGM(3,chunkSize)
INTEGER                       :: iBGMElem,nBGMElems,TotalNbrOfRecvParts
LOGICAL                       :: InsideMyBGM(chunkSize)
! Temporary state arrays
REAL,ALLOCATABLE              :: chunkState(:,:)
! MPI Communication
INTEGER                       :: ALLOCSTAT,PartCommSize,ParticleIndexNbr
INTEGER                       :: InitGroup,tProc
INTEGER                       :: msg_status(1:MPI_STATUS_SIZE),messageSize
INTEGER                       :: nRecvParticles,nSendParticles
REAL,ALLOCATABLE              :: recvPartPos(:)
!===================================================================================================================================
InitGroup = Species(FractNbr)%Init(iInit)%InitCOMM

! Arrays for communication of particles not located in final element
ALLOCATE( PartMPIInsert%nPartsSend  (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPIInsert%nPartsRecv  (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPIInsert%SendRequest (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPIInsert%RecvRequest (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPIInsert%send_message(  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) &
  CALL ABORT(__STAMP__,' Cannot allocate particle emission MPI arrays! ALLOCSTAT',ALLOCSTAT)

ALLOCATE( PartMPILocate%nPartsSend (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPILocate%nPartsRecv (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPILocate%SendRequest(2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPILocate%RecvRequest(2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , EmissionRecvBuf          (  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , EmissionSendBuf          (  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) &
  CALL ABORT(__STAMP__,' Cannot allocate particle emission MPI arrays! ALLOCSTAT',ALLOCSTAT)

PartMPIInsert%nPartsSend=0
PartMPIInsert%nPartsRecv=0

! Arrays for communication of particles located in final element. Reuse particle_mpi infrastructure wherever possible
PartCommSize   = 0
PartCommSize   = PartCommSize + 3                            ! Emission position (physical space)
IF(DoRefMapping) PartCommSize = PartCommSize+3               ! Emission position (reference space)
!PartCommSize   = PartCommSize + 1                            ! Species-ID
PartCommSize   = PartCommSize + 1                            ! ID of element

PartMPILocate%nPartsSend=0
PartMPILocate%nPartsRecv=0

! Temporary array to hold ElemID of located particles
ALLOCATE( chunkState(PartCommSize,chunkSize)                                                &
        , STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) &
  CALL ABORT(__STAMP__,' Cannot allocate particle emission MPI arrays! ALLOCSTAT',ALLOCSTAT)

chunkState = -1

!--- 1/4 Open receive buffer (located and non-located particles)
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  !--- MPI_IRECV lengths of lists of particles entering local mesh
  CALL MPI_IRECV( PartMPIInsert%nPartsRecv(:,iProc)                           &
                , 2                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1011                                                        &
                , PartMPI%InitGroup(InitGroup)%COMM                           &
                , PartMPIInsert%RecvRequest(1,iProc)                          &
                , IERROR)
  CALL MPI_IRECV( PartMPILocate%nPartsRecv(:,iProc)                           &
                , 2                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1111                                                        &
                , PartMPI%InitGroup(InitGroup)%COMM                           &
                , PartMPILocate%RecvRequest(1,iProc)                          &
                , IERROR)
END DO

! Identify particles that are on the node (or in the halo region of the node) or on other nodes
DO i=1,chunkSize
  ! Set BGM cell index
  ASSOCIATE( xMin   => (/GEO%xminglob  , GEO%yminglob  , GEO%zminglob/)  ,    &
             BGMMin => (/GEO%FIBGMimin , GEO%FIBGMjmin , GEO%FIBGMkmin/) ,    &
             BGMMax => (/GEO%FIBGMimax , GEO%FIBGMjmax , GEO%FIBGMkmax/) )
    DO iDir = 1, 3
      ijkBGM(iDir,i) = INT((particle_positions(DimSend*(i-1)+iDir)-xMin(iDir))/GEO%FIBGMdeltas(iDir))+1
    END DO ! iDir = 1, 3

    ! Check BGM cell index
    InsideMyBGM(i)=.TRUE.
    DO iDir = 1, 3
      IF(ijkBGM(iDir,i).LT.BGMMin(iDir)) THEN
        InsideMyBGM(i)=.FALSE.
        EXIT
      END IF
      IF(ijkBGM(iDir,i).GT.BGMMax(iDir)) THEN
        InsideMyBGM(i)=.FALSE.
        EXIT
      END IF
    END DO ! iDir = 1, 3
  END ASSOCIATE

  IF(InsideMyBGM(i)) THEN
    !--- check all cells associated with this background mesh cell
    nBGMElems = FIBGM_nElems(ijkBGM(1,i),ijkBGM(2,i),ijkBGM(3,i))

    DO iBGMElem = 1, nBGMElems
      ElemID = FIBGM_Element(FIBGM_offsetElem(ijkBGM(1,i),ijkBGM(2,i),ijkBGM(3,i))+iBGMElem)

      ! Check if element is on node (or halo region of node)
      IF(ElemInfo_Shared(ELEM_HALOFLAG,ElemID).EQ.0) THEN ! it is 0 or 2
        InsideMyBGM(i) = .FALSE.
      END IF ! ElemInfo_Shared(ELEM_HALOFLAG,ElemID).NE.1
    END DO ! iBGMElem = 1, nBGMElems
  END IF ! InsideMyBGM(i)
END DO ! i = 1, chunkSize

!--- Find non-local particles for sending to other nodes
DO i = 1, chunkSize
  IF(.NOT.InsideMyBGM(i)) THEN
    !--- check all cells associated with this background mesh cell. The
    !--- information is still present as it was set in particle_bgm.f90
    nBGMElems = FIBGM_nElems(ijkBGM(1,i),ijkBGM(2,i),ijkBGM(3,i))

    ! Loop over all BGM elements and count number of particles per procs for sending
    DO iBGMElem = 1, nBGMElems
      ElemID = FIBGM_Element(FIBGM_offsetElem(ijkBGM(1,i),ijkBGM(2,i),ijkBGM(3,i))+iBGMElem)
      ProcID = ElemToProcID_Shared(ElemID)

      tProc=PartMPI%InitGroup(InitGroup)%CommToGroup(ProcID)
      IF(tProc.EQ.-1) CYCLE ! Processor is not on emission communicator
      PartMPIInsert%nPartsSend(1,tProc) = PartMPIInsert%nPartsSend(1,tProc)+1
    END DO
  END IF ! .NOT.InsideMyBGM(i)
END DO ! i = 1, chunkSize

!--- 2/4 Send number of non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  ! send particles
  !--- MPI_ISEND lengths of lists of particles leaving local mesh
  CALL MPI_ISEND( PartMPIInsert%nPartsSend( 1,iProc)                          &
                , 1                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1011                                                        &
                , PartMPI%InitGroup(InitGroup)%COMM                           &
                , PartMPIInsert%SendRequest(1,iProc)                          &
                , IERROR)
  IF (PartMPIInsert%nPartsSend(1,iProc).GT.0) THEN
    MessageSize = DimSend*PartMPIInsert%nPartsSend(1,iProc)*DimSend
    ALLOCATE( PartMPIInsert%send_message(iProc)%content(MessageSize), STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) &
      CALL ABORT(__STAMP__,'  Cannot allocate emission PartSendBuf, local ProcId, ALLOCSTAT',iProc,REAL(ALLOCSTAT))
  END IF
END DO


!--- 3/4 Send actual non-located particles
PartMPIInsert%nPartsSend(2,:)=0
DO i = 1, chunkSize
  IF(.NOT.InsideMyBGM(i)) THEN
    !--- check all cells associated with this background mesh cell
    nBGMElems = FIBGM_nElems(ijkBGM(1,i),ijkBGM(2,i),ijkBGM(3,i))

    ! Loop over all BGM elements and count number of particles per procs for sending
    DO iBGMElem = 1, nBGMElems
      ElemID = FIBGM_Element(FIBGM_offsetElem(ijkBGM(1,i),ijkBGM(2,i),ijkBGM(3,i))+iBGMElem)
      ProcID = ElemToProcID_Shared(ElemID)

      tProc=PartMPI%InitGroup(InitGroup)%CommToGroup(ProcID)
      ! Processor is not on emission communicator
      IF (tProc.EQ.-1) CYCLE

      ! Assemble message
      iPos = PartMPIInsert%nPartsSend(2,tProc) * DimSend
      PartMPIInsert%send_message(tProc)%content(iPos+1:iPos+3) = particle_positions(DimSend*(i-1)+1:DimSend*i)

      ! Counter of previous particles on proc
      PartMPIInsert%nPartsSend(2,tProc)=PartMPIInsert%nPartsSend(2,tProc) + 1
    END DO
  END IF ! .NOT.InsideMyBGM(i)
END DO ! i = 1, chunkSize


!--- 4/4 Receive actual non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  CALL MPI_WAIT(PartMPIInsert%SendRequest(1,iProc),msg_status(:),IERROR)
  IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  CALL MPI_WAIT(PartMPIInsert%RecvRequest(1,iProc),msg_status(:),IERROR)
  IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
END DO

! recvPartPos holds particles from ALL procs
ALLOCATE(recvPartPos(1:SUM(PartMPIInsert%nPartsRecv(1,:)*DimSend)), STAT=ALLOCSTAT)
TotalNbrOfRecvParts = 0
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  IF (PartMPIInsert%nPartsRecv(1,iProc).GT.0) THEN
  !--- MPI_IRECV lengths of lists of particles entering local mesh
    CALL MPI_IRECV( recvPartPos(TotalNbrOfRecvParts*DimSend+1)                &
                  , DimSend*PartMPIInsert%nPartsRecv(1,iProc)                 &
                  , MPI_DOUBLE_PRECISION                                      &
                  , iProc                                                     &
                  , 1022                                                      &
                  , PartMPI%InitGroup(InitGroup)%COMM                         &
                  , PartMPIInsert%RecvRequest(2,iProc)                        &
                  , IERROR)
    TotalNbrOfRecvParts = TotalNbrOfRecvParts + PartMPIInsert%nPartsRecv(1,iProc)
  END IF
  !--- (non-blocking:) send messages to all procs receiving particles from myself
  IF (PartMPIInsert%nPartsSend(2,iProc).GT.0) THEN
    CALL MPI_ISEND( PartMPIInsert%send_message(iProc)%content                 &
                  , DimSend*PartMPIInsert%nPartsSend(2,iProc)                 &
                  , MPI_DOUBLE_PRECISION                                      &
                  , iProc                                                     &
                  , 1022                                                      &
                  , PartMPI%InitGroup(InitGroup)%COMM                         &
                  , PartMPIInsert%SendRequest(2,iProc)                        &
                  , IERROR)
  END IF
END DO

mySumOfMatchedParticles = 0
ParticleIndexNbr        = 1

!--- Locate local (node or halo of node) particles
DO i = 1, chunkSize
  IF(InsideMyBGM(i))THEN
    ! We cannot call LocateParticleInElement because we do not know the final PartID yet. Locate the position and fill PartState
    ! manually if we got a hit
    ElemID = SinglePointToElement(particle_positions(DimSend*(i-1)+1:DimSend*(i-1)+3),doHALO=.TRUE.)
    ! Checked every possible cell and didn't find it. Apparently, we emitted the particle outside the domain
    IF(ElemID.EQ.-1) CYCLE

    ! Only keep the particle if it belongs on the current proc. Otherwise prepare to send it to the correct proc
    ! TODO: Implement U_Shared, so we can finish emission on this proc and send the fully initialized particle (i.e. including
    ! velocity)
    ProcID = ElemToProcID_Shared(ElemID)
    IF (ProcID.NE.myRank) THEN
      ! ProcID on emission communicator
      tProc=PartMPI%InitGroup(InitGroup)%CommToGroup(ProcID)
      ! Processor is not on emission communicator
      IF(tProc.EQ.-1) &
        CALL ABORT(__STAMP__,'Error in particle_mpi_emission: proc not on emission communicator')

      PartMPILocate%nPartsSend(1,tProc)= PartMPILocate%nPartsSend(1,tProc)+1

      ! Assemble temporary PartState to send the final particle position
      chunkState(1:3,i) = particle_positions(DimSend*(i-1)+1:DimSend*(i-1)+3)
      IF (DoRefMapping) THEN
        CALL GetPositionInRefElem(chunkState(1:3,i),chunkState(4:6,i),ElemID)
!        chunkState(7,i) = Species(FractNbr)
        chunkState(7,i) = REAL(ElemID,KIND=8)
      ELSE
!        chunkState(4,i) = Species(FractNbr)
        chunkState(4,i) = REAL(ElemID,KIND=8)
      END IF ! DoRefMapping
    ! Located particle on local proc.
    ELSE
      ! Find a free position in the PDM array
      IF ((i.EQ.1).OR.PDM%ParticleInside(ParticleIndexNbr)) THEN
        ParticleIndexNbr = PDM%nextFreePosition(mySumOfMatchedParticles + 1 + PDM%CurrentNextFreePosition)
      END IF
      IF (ParticleIndexNbr.NE.0) THEN
        ! Fill the PartState manually to avoid a second localization
        PartState(1:DimSend,ParticleIndexNbr) = particle_positions(DimSend*(i-1)+1:DimSend*(i-1)+DimSend)
        PDM%ParticleInside( ParticleIndexNbr) = .TRUE.
        IF (DoRefMapping) THEN
          CALL GetPositionInRefElem(PartState(1:3,ParticleIndexNbr),PartPosRef(1:3,ParticleIndexNbr),ElemID)
        END IF ! DoRefMapping
        PEM%Element(ParticleIndexNbr)         = ElemID
      ELSE
        CALL ABORT(__STAMP__,'ERROR in ParticleMPIEmission:ParticleIndexNbr.EQ.0 - maximum nbr of particles reached?')
      END IF
      mySumOfMatchedParticles = mySumOfMatchedParticles + 1
    END IF ! ElemID.EQ.-1
  END IF ! InsideMyBGM(i)
END DO ! i = 1, chunkSize

!---  /  Send number of located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  ! send particles
  !--- MPI_ISEND lengths of lists of particles leaving local mesh
  CALL MPI_ISEND( PartMPILocate%nPartsSend( 1,iProc)                          &
                , 1                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1111                                                        &
                , PartMPI%InitGroup(InitGroup)%COMM                           &
                , PartMPILocate%SendRequest(1,iProc)                          &
                , IERROR)
  IF (PartMPILocate%nPartsSend(1,iProc).GT.0) THEN
    MessageSize = PartMPILocate%nPartsSend(1,iProc)*PartCommSize
    ALLOCATE(EmissionSendBuf(iProc)%content(MessageSize),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) &
      CALL ABORT(__STAMP__,'  Cannot allocate emission EmissionSendBuf, local ProcId, ALLOCSTAT',iProc,REAL(ALLOCSTAT))
  END IF
END DO

!--- 3/4 Send actual located particles. PartState is filled in LocateParticleInElement
PartMPILocate%nPartsSend(2,:) = 0
DO i = 1, chunkSize
  ElemID = INT(chunkState(PartCommSize,i))
  ! Skip non-located particles
  IF(ElemID.EQ.-1) CYCLE
  ProcID = ElemToProcID_Shared(ElemID)
  IF (ProcID.NE.myRank) THEN
    ! ProcID on emission communicator
    tProc=PartMPI%InitGroup(InitGroup)%CommToGroup(ProcID)
    ! Processor is not on emission communicator
    IF(tProc.EQ.-1) CYCLE

    ! Assemble message
    iPos = PartMPILocate%nPartsSend(2,tProc) * PartCommSize
    EmissionSendBuf(tProc)%content(1+iPos:PartCommSize+iPos) = chunkState(1:PartCommSize,i)

    ! Counter of previous particles on proc
    PartMPILocate%nPartsSend(2,tProc) = PartMPILocate%nPartsSend(2,tProc) + 1
  END IF ! ProcID.NE.myRank
END DO ! i = 1, chunkSize

!--- 4/4 Receive actual non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  CALL MPI_WAIT(PartMPILocate%SendRequest(1,iProc),msg_status(:),IERROR)
  IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  CALL MPI_WAIT(PartMPILocate%RecvRequest(1,iProc),msg_status(:),IERROR)
  IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
END DO

DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  ! Allocate receive array and open receive buffer if expecting particles from iProc
  IF (PartMPILocate%nPartsRecv(1,iProc).GT.0) THEN
    nRecvParticles = PartMPILocate%nPartsRecv(1,iProc)
    MessageSize    = nRecvParticles * PartCommSize
    ALLOCATE(EmissionRecvBuf(iProc)%content(MessageSize),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) &
      CALL ABORT(__STAMP__,'  Cannot allocate emission EmissionRecvBuf, local ProcId, ALLOCSTAT',iProc,REAL(ALLOCSTAT))

    !--- MPI_IRECV lengths of lists of particles entering local mesh
    CALL MPI_IRECV( EmissionRecvBuf(iProc)%content                             &
                  , MessageSize                                                &
                  , MPI_DOUBLE_PRECISION                                       &
                  , iProc                                                      &
                  , 1122                                                       &
                  , PartMPI%InitGroup(InitGroup)%COMM                          &
                  , PartMPILocate%RecvRequest(2,iProc)                         &
                  , IERROR )
    IF(IERROR.NE.MPI_SUCCESS) &
      CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
  END IF
  !--- (non-blocking:) send messages to all procs receiving particles from myself
  IF (PartMPILocate%nPartsSend(2,iProc).GT.0) THEN
    nSendParticles = PartMPILocate%nPartsSend(1,iProc)
    MessageSize    = nSendParticles * PartCommSize
    CALL MPI_ISEND( EmissionSendBuf(iProc)%content                             &
                  , MessageSize                                                &
                  , MPI_DOUBLE_PRECISION                                       &
                  , iProc                                                      &
                  , 1122                                                       &
                  , PartMPI%InitGroup(InitGroup)%COMM                          &
                  , PartMPILocate%SendRequest(2,iProc)                         &
                  , IERROR )
    IF(IERROR.NE.MPI_SUCCESS) &
      CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
  END IF
END DO

!--- 5/4 Finish communication of actual non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  IF (PartMPIInsert%nPartsSend(1,iProc).GT.0) THEN
    CALL MPI_WAIT(PartMPIInsert%SendRequest(2,iProc),msg_status(:),IERROR)
    IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  END IF
  IF (PartMPIInsert%nPartsRecv(1,iProc).GT.0) THEN
    CALL MPI_WAIT(PartMPIInsert%RecvRequest(2,iProc),msg_status(:),IERROR)
    IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  END IF
END DO

!--- 6/4 Try to locate received non-located particles
TotalNbrOfRecvParts = SUM(PartMPIInsert%nPartsRecv(1,:))
DO i = 1,TotalNbrOfRecvParts
  ! We cannot call LocateParticleInElement because we do not know the final PartID yet. Locate the position and fill PartState
  ! manually if we got a hit
  ElemID = SinglePointToElement(recvPartPos(DimSend*(i-1)+1:DimSend*(i-1)+3),doHALO=.FALSE.)
  ! Checked every possible cell and didn't find it. Apparently, we emitted the particle outside the domain
  IF(ElemID.EQ.-1) CYCLE

  ! Only keep the particle if it belongs on the current proc. Trust the other procs to do their jobs and locate it if needed
  IF (ElemToProcID_Shared(ElemID).NE.myRank) CYCLE

  ! Find a free position in the PDM array
  ParticleIndexNbr = PDM%nextFreePosition(mySumOfMatchedParticles + 1 + PDM%CurrentNextFreePosition)
  IF (ParticleIndexNbr.NE.0) THEN
    ! Fill the PartState manually to avoid a second localization
    PartState(1:3,ParticleIndexNbr) = recvPartPos(DimSend*(i-1)+1:DimSend*(i-1)+3)
    IF (DoRefMapping) THEN
      PartPosRef(1:3,ParticleIndexNbr) = recvPartPos(DimSend*(i-1)+4:DimSend*(i-1)+6)
    END IF ! DoRefMapping
    PEM%Element(ParticleIndexNbr)    = INT(recvPartPos(DimSend*(i-1)+PartCommSize),KIND=4)

    PDM%ParticleInside( ParticleIndexNbr) = .TRUE.
    IF (DoRefMapping) THEN
      CALL GetPositionInRefElem(PartState(1:3,ParticleIndexNbr),PartPosRef(1:3,ParticleIndexNbr),ElemID)
    END IF ! DoRefMapping
  ELSE
    CALL ABORT(__STAMP__,'ERROR in ParticleMPIEmission:ParticleIndexNbr.EQ.0 - maximum nbr of particles reached?')
  END IF
  mySumOfMatchedParticles = mySumOfMatchedParticles + 1
END DO

!--- 7/4 Finish communication of actual non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  IF (PartMPILocate%nPartsSend(1,iProc).GT.0) THEN
    CALL MPI_WAIT(PartMPILocate%SendRequest(2,iProc),msg_status(:),IERROR)
    IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  END IF
  IF (PartMPILocate%nPartsRecv(1,iProc).GT.0) THEN
    CALL MPI_WAIT(PartMPILocate%RecvRequest(2,iProc),msg_status(:),IERROR)
    IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  END IF
END DO

!--- 8/4 Write located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE
  IF (PartMPILocate%nPartsRecv(1,iProc).EQ.0) CYCLE

  DO i = 1,PartMPILocate%nPartsRecv(1,iProc)
    ! Find a free position in the PDM array
    ParticleIndexNbr = PDM%nextFreePosition(mySumOfMatchedParticles + 1 + PDM%CurrentNextFreePosition)
    IF (ParticleIndexNbr.NE.0) THEN
      ! Fill the PartState manually to avoid a second localization
      PartState(1:3,ParticleIndexNbr) = EmissionRecvBuf(iProc)%content(PartCommSize*(i-1)+1:PartCommSize*(i-1)+3)
      IF (DoRefMapping) THEN
        PartPosRef(1:3,ParticleIndexNbr) = EmissionRecvBuf(iProc)%content(PartCommSize*(i-1)+4:PartCommSize*(i-1)+6)
      END IF ! DoRefMapping
      PEM%Element(ParticleIndexNbr)    = INT(EmissionRecvBuf(iProc)%content(PartCommSize*(i)),KIND=4)
!      WRITE(*,*) ParticleIndexNbr,PEM%Element(ParticleIndexNbr)

      PDM%ParticleInside( ParticleIndexNbr) = .TRUE.
      IF (DoRefMapping) THEN
        CALL GetPositionInRefElem(PartState(1:3,ParticleIndexNbr),PartPosRef(1:3,ParticleIndexNbr),PEM%Element(ParticleIndexNbr))
      END IF ! DoRefMapping
    ELSE
      CALL ABORT(__STAMP__,'ERROR in ParticleMPIEmission:ParticleIndexNbr.EQ.0 - maximum nbr of particles reached?')
    END IF
    mySumOfMatchedParticles = mySumOfMatchedParticles + 1
  END DO
END DO

!--- Clean up
SDEALLOCATE(recvPartPos)
SDEALLOCATE(chunkState)
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  SDEALLOCATE(EmissionRecvBuf(iProc)%content)
  SDEALLOCATE(EmissionSendBuf(iProc)%content)
END DO
SDEALLOCATE(PartMPIInsert%nPartsSend)
SDEALLOCATE(PartMPIInsert%nPartsRecv)
SDEALLOCATE(PartMPIInsert%SendRequest)
SDEALLOCATE(PartMPIInsert%RecvRequest)
SDEALLOCATE(PartMPIInsert%send_message)

SDEALLOCATE(PartMPILocate%nPartsSend)
SDEALLOCATE(PartMPILocate%nPartsRecv)
SDEALLOCATE(PartMPILocate%SendRequest)
SDEALLOCATE(PartMPILocate%RecvRequest)
SDEALLOCATE(EmissionRecvBuf)
SDEALLOCATE(EmissionSendBuf)

END SUBROUTINE SendEmissionParticlesToProcs


!SUBROUTINE FinalizeEmissionParticlesToProcs()
!!----------------------------------------------------------------------------------------------------------------------------------!
!! Finalizes the MPI communication during particle emission
!!----------------------------------------------------------------------------------------------------------------------------------!
!! MODULES                                                                                                                          !
!USE MOD_Globals
!USE MOD_Particle_MPI_Vars      ,ONLY: PartMPIInsert,PartMPILocate
!USE MOD_Particle_MPI_Vars      ,ONLY: EmissionSendBuf,EmissionRecvBuf
!USE MOD_Particle_Vars          ,ONLY: Species,nSpecies
!! IMPLICIT VARIABLE HANDLING
!IMPLICIT NONE
!!----------------------------------------------------------------------------------------------------------------------------------!
!! INPUT / OUTPUT VARIABLES
!!-----------------------------------------------------------------------------------------------------------------------------------
!! LOCAL VARIABLES
!INTEGER                       :: i,iInit,InitGroup
!!===================================================================================================================================
!DO i = 1,nSpecies
!  DO iInit = 1, Species(i)%NumberOfInits
!    InitGroup = Species(i)%Init(iInit)%InitCOMM
!
!    ! Arrays for communication of particles not located in final element
!    SDEALLOCATE(PartMPIInsert%nPartsSend)
!    SDEALLOCATE(PartMPIInsert%nPartsRecv)
!    SDEALLOCATE(PartMPIInsert%SendRequest)
!    SDEALLOCATE(PartMPIInsert%RecvRequest)
!    SDEALLOCATE(PartMPIInsert%send_message)
!    SDEALLOCATE(PartMPILocate%nPartsSend)
!    SDEALLOCATE(PartMPILocate%nPartsRecv)
!    SDEALLOCATE(PartMPILocate%SendRequest)
!    SDEALLOCATE(PartMPILocate%RecvRequest)
!    SDEALLOCATE(EmissionRecvBuf)
!    SDEALLOCATE(EmissionSendBuf)
!  END DO
!END DO
!
!END SUBROUTINE FinalizeEmissionParticlesToProcs


SUBROUTINE FinalizeEmissionComm()
!===================================================================================================================================
! Finalize emission communicators for particle emission regions
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Vars          ,ONLY: Species,nSpecies
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPI
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                       :: iSpec,iInit,nInitRegions
!===================================================================================================================================

nInitRegions = 0
DO iSpec = 1,nSpecies
  DO iInit = Species(iSpec)%StartnumberOfInits, Species(iSpec)%NumberOfInits
    nInitRegions = nInitRegions+1
    IF (PartMPI%InitGroup(nInitRegions)%COMM.NE.MPI_COMM_NULL) THEN
      SDEALLOCATE(PartMPI%InitGroup(nInitRegions)%GroupToComm)
      SDEALLOCATE(PartMPI%InitGroup(nInitRegions)%CommToGroup)
    END IF
  END DO
END DO

SDEALLOCATE( PartMPI%InitGroup)

END SUBROUTINE FinalizeEmissionComm


FUNCTION BoxInProc(CartNodes,nNodes)
!===================================================================================================================================
! check if bounding box is on proc
!===================================================================================================================================
! MODULES
USE MOD_Particle_Mesh_Vars,       ONLY:GEO
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)   :: CartNodes(1:3,1:nNodes)
INTEGER,INTENT(IN):: nNodes
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
LOGICAL           :: BoxInProc
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: xmin,xmax,ymin,ymax,zmin,zmax,testval
!===================================================================================================================================

BoxInProc=.FALSE.
! get background of nodes
xmin=HUGE(1)
xmax=-HUGE(1)
ymin=HUGE(1)
ymax=-HUGE(1)
zmin=HUGE(1)
zmax=-HUGE(1)
testval = CEILING((MINVAL(CartNodes(1,:))-GEO%xminglob)/GEO%FIBGMdeltas(1))
xmin    = MIN(xmin,testval)
testval = CEILING((MAXVAL(CartNodes(1,:))-GEO%xminglob)/GEO%FIBGMdeltas(1))
xmax    = MAX(xmax,testval)
testval = CEILING((MINVAL(CartNodes(2,:))-GEO%yminglob)/GEO%FIBGMdeltas(2))
ymin    = MIN(ymin,testval)
testval = CEILING((MAXVAL(CartNodes(2,:))-GEO%yminglob)/GEO%FIBGMdeltas(2))
ymax    = MAX(ymax,testval)
testval = CEILING((MINVAL(CartNodes(3,:))-GEO%zminglob)/GEO%FIBGMdeltas(3))
zmin    = MIN(zmin,testval)
testval = CEILING((MAXVAL(CartNodes(3,:))-GEO%zminglob)/GEO%FIBGMdeltas(3))
zmax    = MAX(zmax,testval)

IF(    ((xmin.LE.GEO%FIBGMimax).AND.(xmax.GE.GEO%FIBGMimin)) &
  .AND.((ymin.LE.GEO%FIBGMjmax).AND.(ymax.GE.GEO%FIBGMjmin)) &
  .AND.((zmin.LE.GEO%FIBGMkmax).AND.(zmax.GE.GEO%FIBGMkmin)) ) BoxInProc=.TRUE.

END FUNCTION BoxInProc


FUNCTION PointInProc(CartNode)
!===================================================================================================================================
! check if point is on proc
!===================================================================================================================================
! MODULES
USE MOD_Particle_Mesh_Vars,       ONLY:GEO
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)   :: CartNode(1:3)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
LOGICAL           :: PointInProc
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: xmin,xmax,ymin,ymax,zmin,zmax,testval
!===================================================================================================================================

PointInProc=.FALSE.
! get background of nodes
xmin=HUGE(1)
xmax=-HUGE(1)
ymin=HUGE(1)
ymax=-HUGE(1)
zmin=HUGE(1)
zmax=-HUGE(1)
testval = CEILING((CartNode(1)-GEO%xminglob)/GEO%FIBGMdeltas(1))
xmin    = MIN(xmin,testval)
testval = CEILING((CartNode(1)-GEO%xminglob)/GEO%FIBGMdeltas(1))
xmax    = MAX(xmax,testval)
testval = CEILING((CartNode(2)-GEO%yminglob)/GEO%FIBGMdeltas(2))
ymin    = MIN(ymin,testval)
testval = CEILING((CartNode(2)-GEO%yminglob)/GEO%FIBGMdeltas(2))
ymax    = MAX(ymax,testval)
testval = CEILING((CartNode(3)-GEO%zminglob)/GEO%FIBGMdeltas(3))
zmin    = MIN(zmin,testval)
testval = CEILING((CartNode(3)-GEO%zminglob)/GEO%FIBGMdeltas(3))
zmax    = MAX(zmax,testval)

IF(    ((xmin.LE.GEO%FIBGMimax).AND.(xmax.GE.GEO%FIBGMimin)) &
  .AND.((ymin.LE.GEO%FIBGMjmax).AND.(ymax.GE.GEO%FIBGMjmin)) &
  .AND.((zmin.LE.GEO%FIBGMkmax).AND.(zmax.GE.GEO%FIBGMkmin)) ) PointInProc=.TRUE.

END FUNCTION PointInProc
#endif /*USE_MPI*/

END MODULE MOD_Particle_MPI_Emission
