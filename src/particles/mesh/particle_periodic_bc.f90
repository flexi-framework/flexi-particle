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

!===================================================================================================================================
! Module initialization of periodic vectors for particle treatment
!===================================================================================================================================
MODULE MOD_Particle_Periodic_BC
! MODULES
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------

INTERFACE InitPeriodicBC
  MODULE PROCEDURE InitPeriodicBC
END INTERFACE

PUBLIC :: InitPeriodicBC
!===================================================================================================================================

CONTAINS

SUBROUTINE InitPeriodicBC()
!===================================================================================================================================
! Computes the periodic-displacement vector
! Both periodic sides have to be planer and parallel!
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_ReadInTools,            ONLY:GETINT,GETREALARRAY
USE MOD_Particle_Mesh_Vars,     ONLY:GEO
USE MOD_Particle_Boundary_Vars, ONLY:PartBound
USE MOD_Mesh_Vars,              ONLY:BoundaryType,nBCs
#if USE_MPI
USE MOD_Particle_Vars,          ONLY:PDM
USE MOD_Particle_MPI_Vars,      ONLY:PartShiftVector
#endif /*MPI*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                :: iVec,iBC
!CHARACTER(32)          :: hilf
LOGICAL                :: hasPeriodic
!===================================================================================================================================

!GEO%nPeriodicVectors       = GETINT('Part-nPeriodicVectors','0')

! sanity check with DG. Both must be either periodic or non-periodic.
hasPeriodic = .FALSE.
DO iBC=1,nBCs
  IF(BoundaryType(iBC,BC_TYPE).EQ.1) hasPeriodic=.TRUE.
END DO ! iBC=1,nBCs

DO iVec = 1, SIZE(PartBound%TargetBoundCond)
  IF((PartBound%TargetBoundCond(iVec).EQ.PartBound%PeriodicBC).AND.(GEO%nPeriodicVectors.EQ.0)) &
    CALL abort(__STAMP__,'Part-PeriodicVectors need to be assigned in the ini file')
END DO

! read-in periodic-vectors for particles
!ALLOCATE(GEO%PeriodicVectors(1:3,1:GEO%nPeriodicVectors))
!DO iVec = 1, GEO%nPeriodicVectors
!  WRITE(UNIT=hilf,FMT='(I0)') iVec
!  GEO%PeriodicVectors(1:3,iVec) = GETREALARRAY('Part-PeriodicVector'//TRIM(hilf),3,'1.,0.,0.')
!END DO

CALL GetPeriodicVectors()

#if USE_MPI
SDEALLOCATE(PartShiftVector)
IF (GEO%nPeriodicVectors.GT.0) THEN
  ALLOCATE(PartShiftVector(1:3,1:PDM%maxParticleNumber))
  PartShiftVector = 0.
END IF
#endif /*MPI*/

END SUBROUTINE InitPeriodicBC


SUBROUTINE GetPeriodicVectors()
!===================================================================================================================================
! Check the periodic vectors for consistency
! For particles, each periodic vector has to satisfy following conditions
! 1) only a Cartesian displacement/ periodicity is supported, e.g. periodicity in x,y,z
! 2) Mesh has to fit into the FIBGM, therefore, the displacement is a multiple of the FIBGM-delta
!    Periodic displacement has to be multiple of BGMdeltas of deposition method
!
! NEW: Cartesian mesh is required for shape-function deposition
!      All other cases: non-Cartesian periodic vectors are possible but not allowed!
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Mesh_Vars, ONLY: GEO
!----------------------------------------------------------------------------------------------------------------------------------
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!LOGICAL                :: directions(1:3)
!INTEGER                :: iPV
REAL                   :: eps(1:3)!,dummy
!===================================================================================================================================

LOGWRITE(*,*) 'nPeriodicVectors = ',GEO%nPeriodicVectors
IF ((GEO%nPeriodicVectors.GT.3).OR.(GEO%nPeriodicVectors.LT.0)) &
  CALL abort(__STAMP__,'nPeriodicVectors must be >= 0 and <= 3!',GEO%nPeriodicVectors,999.)

GEO%directions = .FALSE.
IF (GEO%nPeriodicVectors.EQ.0) RETURN

SDEALLOCATE(GEO%DirPeriodicVectors)
ALLOCATE(GEO%DirPeriodicVectors(1:GEO%nPeriodicVectors))

!! check if all periodic vectors are cartesian
!!directions(1:3)=.FALSE.
!DO iPV = 1,GEO%nPeriodicVectors
!  LOGWRITE(*,*)'PeriodicVectors(1:3),',iPV,')=',GEO%PeriodicVectors(1:3,iPV)
!IF (GEO%PeriodicVectors(1,iPV).NE.0) THEN
!  IF ((GEO%PeriodicVectors(2,iPV).NE.0).OR.(GEO%PeriodicVectors(3,iPV).NE.0)) &
!    CALL abort(__STAMP__,'Periodic Vector not in Cartesian direction!',iPV)
!
!  GEO%DirPeriodicVectors(iPV) = 1
!  IF (.NOT.GEO%directions(1)) THEN
!    GEO%directions(1) = .TRUE.
!  ELSE
!    CALL abort(__STAMP__,'2 Periodic Vectors in x-direction!',iPV)
!  END IF
!ELSE IF (GEO%PeriodicVectors(2,iPV).NE.0) THEN
!  IF ((GEO%PeriodicVectors(1,iPV).NE.0).OR.(GEO%PeriodicVectors(3,iPV).NE.0)) &
!    CALL abort(__STAMP__,'Periodic Vector not in Cartesian direction!',iPV)
!
!  GEO%DirPeriodicVectors(iPV) = 2
!  IF (.NOT.GEO%directions(2)) THEN
!    GEO%directions(2) = .TRUE.
!  ELSE
!    CALL abort(__STAMP__,'2 Periodic Vectors in y-direction!',iPV)
!  END IF
!ELSE IF (GEO%PeriodicVectors(3,iPV).NE.0) THEN
!  IF ((GEO%PeriodicVectors(1,iPV).NE.0).OR.(GEO%PeriodicVectors(2,iPV).NE.0)) &
!    CALL abort(__STAMP__,'Periodic Vector not in Cartesian direction!',iPV)
!
!  GEO%DirPeriodicVectors(iPV) = 3
!  IF (.NOT.GEO%directions(3)) THEN
!    GEO%directions(3) = .TRUE.
!  ELSE
!    CALL abort(__STAMP__,'2 Periodic Vectors in z-direction!',iPV)
!  END IF
!ELSE
!  CALL abort(__STAMP__,'Periodic Vector = 0!',iPV)
!END IF
!END DO

! check if periodic vector is multiple of FIBGM-deltas
! some tolerance
eps(1)=1.E-9*(GEO%FIBGMDeltas(1))
eps(2)=1.E-9*(GEO%FIBGMDeltas(2))
eps(3)=1.E-9*(GEO%FIBGMDeltas(3))

IF(ABS(SUM(GEO%PeriodicVectors(1,:))-NINT(SUM(GEO%PeriodicVectors(1,:))/GEO%FIBGMDeltas(1))*GEO%FIBGMDeltas(1)) &
.GT.eps(1)) THEN
ERRWRITE(*,*)'SUM(PeriodicVectors(1,:))   =',SUM(GEO%PeriodicVectors(1,:))
ERRWRITE(*,*)'GEO%FIBGMDeltas(1)          =',GEO%FIBGMDeltas(1)
ERRWRITE(*,*)'1.E-9*(FIBGMDeltas(1))      =',eps(1)
ERRWRITE(*,*)'ABS(SUM-NINT(SUM/D(1))*D(1))=',ABS(SUM(GEO%PeriodicVectors(1,:))-&
                                            NINT(SUM(GEO%PeriodicVectors(1,:))/GEO%FIBGMDeltas(1))*GEO%FIBGMDeltas(1))
CALL abort(__STAMP__,'Periodic Vector in x-direction is not a multiple of FIBGMDeltas!',999, &
  ABS(SUM(GEO%PeriodicVectors(1,:))-NINT(SUM(GEO%PeriodicVectors(1,:))/GEO%FIBGMDeltas(1))*GEO%FIBGMDeltas(1)))
ELSE IF (ABS(SUM(GEO%PeriodicVectors(2,:))-NINT(SUM(GEO%PeriodicVectors(2,:))/GEO%FIBGMDeltas(2))*GEO%FIBGMDeltas(2)) &
       .GT.eps(2)) THEN
ERRWRITE(*,*)'SUM(PeriodicVectors(2,:))   =',SUM(GEO%PeriodicVectors(2,:))
ERRWRITE(*,*)'GEO%FIBGMDeltas(2)          =',GEO%FIBGMDeltas(2)
ERRWRITE(*,*)'1.E-9*(FIBGMDeltas(2))      =',eps(2)
ERRWRITE(*,*)'ABS(SUM-NINT(SUM/D(2))*D(2))=',ABS(SUM(GEO%PeriodicVectors(2,:))-&
                                            NINT(SUM(GEO%PeriodicVectors(2,:))/GEO%FIBGMDeltas(2))*GEO%FIBGMDeltas(2))
CALL abort(__STAMP__,'Periodic Vector in y-direction is not a multiple of FIBGMDeltas!',999, &
  ABS(SUM(GEO%PeriodicVectors(2,:))-NINT(SUM(GEO%PeriodicVectors(2,:))/GEO%FIBGMDeltas(2))*GEO%FIBGMDeltas(2)))
ELSE IF (ABS(SUM(GEO%PeriodicVectors(3,:))-NINT(SUM(GEO%PeriodicVectors(3,:))/GEO%FIBGMDeltas(3))*GEO%FIBGMDeltas(3)) &
       .GT.eps(3)) THEN
ERRWRITE(*,*)'SUM(PeriodicVectors(3,:))   =',SUM(GEO%PeriodicVectors(3,:))
ERRWRITE(*,*)'GEO%FIBGMDeltas(3)          =',GEO%FIBGMDeltas(3)
ERRWRITE(*,*)'1.E-9*(FIBGMDeltas(3))      =',eps(3)
ERRWRITE(*,*)'ABS(SUM-NINT(SUM/D(3))*D(3))=',ABS(SUM(GEO%PeriodicVectors(3,:))-&
                                            NINT(SUM(GEO%PeriodicVectors(3,:))/GEO%FIBGMDeltas(3))*GEO%FIBGMDeltas(3))
CALL abort(__STAMP__,'Periodic Vector in z-direction is not a multiple of FIBGMDeltas!',999,&
  ABS(SUM(GEO%PeriodicVectors(3,:))-NINT(SUM(GEO%PeriodicVectors(3,:))/GEO%FIBGMDeltas(3))*GEO%FIBGMDeltas(3)))
END IF

END SUBROUTINE GetPeriodicVectors

END MODULE MOD_Particle_Periodic_BC
