!=================================================================================================================================
! Copyright (c) 2010-2021  Prof. Claus-Dieter Munz
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

!===================================================================================================================================
! Contains global variables used by the Analyze modules.
!===================================================================================================================================
MODULE MOD_Particle_Analyze_Vars
! MODULES
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
LOGICAL                       :: ParticleAnalyzeInitIsDone = .FALSE.
LOGICAL                       :: DoAnalyze                             ! perform analyze
LOGICAL                       :: DoParticleAnalyze                     ! flag if any particle analyze routine is called
LOGICAL                       :: CalcPartBalance                       ! Particle Power Balance - input and outflow energy of all
                                                                       ! particles
LOGICAL                       :: CalcEkin                              ! Compute the kinetic energy of each species
LOGICAL                       :: doParticlePositionTrack               ! track the particle movement
                                                                       ! stored in .csv format, debug only, no MPI
LOGICAL                       :: doParticleConvergenceTrack            ! track the final particle position, stored in .csv format
LOGICAL                       :: doParticleDispersionTrack             ! track the particle dispersion radius, i.e. the absolute path
LOGICAL                       :: doParticlePathTrack                   ! track the relative particle path
INTEGER                       :: nSpecAnalyze                          ! number of analyzed species 1 or nSpecies+1
INTEGER,ALLOCATABLE           :: nPartIn(:)                            ! Number of entry and leaving particles
INTEGER,ALLOCATABLE           :: nPartOut(:)                           ! Number of entry and leaving particles
INTEGER,ALLOCATABLE           :: nPartInTmp(:)                         ! Number of entry and leaving particles
REAL,ALLOCATABLE              :: PartEkin(:)                           ! kinetic energy of particle
REAL,ALLOCATABLE              :: PartEkinIn(:)                         ! kinetic energy of input particle
REAL,ALLOCATABLE              :: PartEkinOut(:)                        ! kinetic energy of outflow particle
REAL,ALLOCATABLE              :: PartEKinInTmp(:)                      ! kinetic energy of input particle (tmp)
REAL,ALLOCATABLE              :: PartPath(:,:)                         ! absolute particle path (used for dispersion calculation)

REAL                          :: TimeSample

INTEGER                       :: RPP_MaxBufferSize
INTEGER                       :: RecordPart
TYPE tPPlane                                    !< Data type representing a single plane
  REAL                        :: pos            !< position of the plane
  INTEGER                     :: dir            !< direction of the normal vector of the plane
  REAL, ALLOCATABLE           :: RPP_Data(:,:)  !< PartState and PartSpecies
  INTEGER                     :: RPP_Records
END TYPE tPPlane
TYPE(tPPlane),ALLOCATABLE     :: RPP_Plane(:)
INTEGER                       :: RPP_nVarNames = 8    ! I have to change it if I insert other variables for recordplanes

END MODULE MOD_Particle_Analyze_Vars
