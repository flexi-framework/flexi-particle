!=================================================================================================================================
! Copyright (c) 2010-2016  Prof. Claus-Dieter Munz 
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
! Module for calculation of particle forces on surfaces for convergence analysis
!===================================================================================================================================

MODULE MOD_Posti_CalcWallParticles
! MODULES
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------
INTERFACE CalcWallParticles
  MODULE PROCEDURE CalcWallParticles
END INTERFACE

PUBLIC :: CalcWallParticles
!==================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Control routine for CalcBodyforces
!==================================================================================================================================
SUBROUTINE CalcWallParticles(AlphaMean,AlphaVar,EkinMean,EkinVar,partForce,maxForce,DoSpecies,Species_opt)
! MODULES
USE MOD_Preproc
USE MOD_Globals
USE MOD_Particle_Globals
USE MOD_Mesh_Vars,              ONLY: nBCSides,BC,nBCs
USE MOD_AnalyzeEquation_Vars,   ONLY: isWall
USE MOD_DSMC_Vars,              ONLY: MacroSurfaceVal
USE MOD_Particle_Analyze_Vars,  ONLY: TimeSample
USE MOD_Particle_Boundary_Vars, ONLY: SurfMesh,SampWall,nSurfSample
USE MOD_Particle_Erosion_Vars,  ONLY: nErosionVars
USE MOD_Posti_CalcWallParticles_Vars
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
REAL,INTENT(OUT)               :: AlphaMean(nBCs)              !< average impact angle per wall BC
REAL,INTENT(OUT)               :: AlphaVar(nBCs)               !< average impact angle variance per wall BC
REAL,INTENT(OUT)               :: EkinMean(nBCs)               !< average kinetic energy per wall BC
REAL,INTENT(OUT)               :: EkinVar(nBCs)                !< average kinetic energy variance per wall BC
REAL,INTENT(OUT)               :: partForce(nBCs)              !< integrated impact force per wall BC
REAL,INTENT(OUT)               :: maxForce(nBCs)               !< max impact force per wall BC
LOGICAL,INTENT(IN)             :: DoSpecies                    !< Flag if a specific species should be analyzed
INTEGER,INTENT(IN),OPTIONAL    :: Species_opt                  !< Current species
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iBC,iSide,p,q,SurfSideID,nShift,nShiftRHS
REAL,ALLOCATABLE               :: SideArea(:)
INTEGER,ALLOCATABLE            :: SideImpacts(:)
REAL                           :: tmpForce,tmpForceX,tmpForceY,tmpForceZ
!==================================================================================================================================
ALLOCATE(SideArea(nBCs))
ALLOCATE(SideImpacts(nBCs))
SideArea  = 0.
SideImpacts=0
tmpForceX = 0.
tmpForceY = 0.
tmpForceZ = 0.
tmpForce  = 0.

AlphaMean = 0.
AlphaVar  = 0.
EkinMean  = 0.
EkinVar   = 0.
partForce = 0.
maxForce  = 0.       

SELECT CASE (TRIM(analyzeString))
! Numerical integral based on face surface area
CASE('surface')
DO iSide=1,nBCSides
    iBC=BC(iSide)
    IF(.NOT.isWall(iBC)) CYCLE
    SurfSideID=SurfMesh%SideIDToSurfID(iSide)
    DO q=1,nSurfSample
        DO p=1,nSurfSample
            IF (.NOT.DoSpecies) THEN
                ! Only consider walls with actual impacts
                IF (SampWall(SurfSideID)%State(1,p,q).EQ.0) CYCLE
                ! Average kinetic energy
                EkinMean(iBC)  = EkinMean(iBC)  + MacroSurfaceVal(3,p,q,SurfSideID) * SurfMesh%SurfaceArea(p,q,SurfSideID)
                EkinVar(iBC)   = EkinVar(iBC)   + MacroSurfaceVal(6,p,q,SurfSideID) * SurfMesh%SurfaceArea(p,q,SurfSideID)
                ! Average impact angle
                AlphaMean(iBC)  = AlphaMean(iBC)  + MacroSurfaceVal(7,p,q,SurfSideID) * SurfMesh%SurfaceArea(p,q,SurfSideID)
                AlphaVar(iBC)   = AlphaVar(iBC)   + MacroSurfaceVal(10,p,q,SurfSideID)* SurfMesh%SurfaceArea(p,q,SurfSideID)
                ! Integrated impact force
                IF (.NOT.ALMOSTZERO(TimeSample)) THEN
                    tmpForceX   = MacroSurfaceVal(11,p,q,SurfSideID)
                    tmpForceY   = MacroSurfaceVal(12,p,q,SurfSideID)
                    tmpForceZ   = MacroSurfaceVal(13,p,q,SurfSideID)
                END IF
                tmpForce    = SQRT(tmpForceX**2 + tmpForceY**2 + tmpForceZ**2)

                partForce(iBC) = partForce(iBC) + tmpForce
                ! Max impact force
                maxForce(iBC)  = MAX(maxForce(iBC),tmpForce)

                SideArea(iBC)  = SideArea(iBC) + SurfMesh%SurfaceArea(p,q,SurfSideID)
            ELSE
                nShift    = Species_opt * (nErosionVars-1)
                ! Only consider walls with actual impacts
                IF (MacroSurfaceVal(1+nShift,p,q,SurfSideID).EQ.0) CYCLE
                ! Average kinetic energy
                EkinMean(iBC)  = EkinMean(iBC)  + MacroSurfaceVal(3+nShift,p,q,SurfSideID) * SurfMesh%SurfaceArea(p,q,SurfSideID)
                EkinVar(iBC)   = EkinVar(iBC)   + MacroSurfaceVal(6+nShift,p,q,SurfSideID) * SurfMesh%SurfaceArea(p,q,SurfSideID)
                ! Average impact angle
                AlphaMean(iBC)  = AlphaMean(iBC)  + MacroSurfaceVal(7+nShift,p,q,SurfSideID) * SurfMesh%SurfaceArea(p,q,SurfSideID)
                AlphaVar(iBC)   = AlphaVar(iBC)   + MacroSurfaceVal(10+nShift,p,q,SurfSideID)* SurfMesh%SurfaceArea(p,q,SurfSideID)
                ! Integrated impact force
                IF (.NOT.ALMOSTZERO(TimeSample)) THEN
                    tmpForceX   = MacroSurfaceVal(11+nShift,p,q,SurfSideID)
                    tmpForceY   = MacroSurfaceVal(12+nShift,p,q,SurfSideID)
                    tmpForceZ   = MacroSurfaceVal(13+nShift,p,q,SurfSideID)
                END IF
                tmpForce    = SQRT(tmpForceX**2 + tmpForceY**2 + tmpForceZ**2)

                partForce(iBC) = partForce(iBC) + tmpForce
                ! Max impact force
                maxForce(iBC)  = MAX(maxForce(iBC),tmpForce)

                SideArea(iBC)  = SideArea(iBC) + SurfMesh%SurfaceArea(p,q,SurfSideID)
            END IF
        END DO
    END DO
END DO

#if USE_MPI
IF(MPIRoot)THEN
  CALL MPI_REDUCE(MPI_IN_PLACE,EkinMean ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,EkinVar  ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,AlphaMean,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,AlphaVar ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,partForce,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,maxForce ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,SideArea ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
ELSE
  CALL MPI_REDUCE(EkinMean        ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(EkinVar         ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(AlphaMean       ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(AlphaVar        ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(partForce       ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(maxForce        ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(SideArea        ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
END IF
#endif

DO iBC=1,nBCs
    IF(.NOT.isWall(iBC)) CYCLE
    IF(ALMOSTZERO(SideArea(iBC))) CYCLE
    EkinMean(iBC)  = EkinMean(iBC)  / SideArea(iBC)
    EkinVar(iBC)   = EkinVar(iBC)   / SideArea(iBC)
    AlphaMean(iBC) = AlphaMean(iBC) / SideArea(iBC)
    AlphaVar(iBC)  = AlphaVar(iBC)  / SideArea(iBC)
END DO

! Numerical integral based on face impact counter
CASE('impacts')
DO iSide=1,nBCSides
    iBC=BC(iSide)
    IF(.NOT.isWall(iBC)) CYCLE
    SurfSideID=SurfMesh%SideIDToSurfID(iSide)
    DO q=1,nSurfSample
        DO p=1,nSurfSample
            IF (.NOT.DoSpecies) THEN
                ! Only consider walls with actual impacts
                IF (SampWall(SurfSideID)%State(1,p,q).EQ.0) CYCLE
                !<<< Welford's algorithm for variance
                !    (count, mean, M2) = existingAggregate
                !    count = count + 1 
                !    delta = newValue - mean
                !    mean = mean + delta / count
                ! Average kinetic energy
                SideImpacts(iBC)=SideImpacts(iBC) + SampWall(SurfSideID)%State(1,p,q)
                EkinMean(iBC)  = EkinMean(iBC)  * (SideImpacts(iBC) - SampWall(SurfSideID)%State(1,p,q))/SideImpacts(iBC)   &
                                 + MacroSurfaceVal(3,p,q,SurfSideID)* SampWall(SurfSideID)%State(1,p,q) /SideImpacts(iBC)
                EkinVar(iBC)   = EkinVar(iBC)   * (SideImpacts(iBC) - SampWall(SurfSideID)%State(1,p,q))/SideImpacts(iBC)   &
                                 + MacroSurfaceVal(6,p,q,SurfSideID)* SampWall(SurfSideID)%State(1,p,q) /SideImpacts(iBC)
                ! Average impact angle
                AlphaMean(iBC)  = AlphaMean(iBC)* (SideImpacts(iBC) - SampWall(SurfSideID)%State(1,p,q))/SideImpacts(iBC)   &
                                + MacroSurfaceVal(7,p,q,SurfSideID) * SampWall(SurfSideID)%State(1,p,q) /SideImpacts(iBC)
                AlphaVar(iBC)   = AlphaVar(iBC) * (SideImpacts(iBC) - SampWall(SurfSideID)%State(1,p,q))/SideImpacts(iBC)   &
                                + MacroSurfaceVal(10,p,q,SurfSideID)* SampWall(SurfSideID)%State(1,p,q) /SideImpacts(iBC)
                ! Integrated impact force
                IF (.NOT.ALMOSTZERO(TimeSample)) THEN
                    tmpForceX   = MacroSurfaceVal(11,p,q,SurfSideID)
                    tmpForceY   = MacroSurfaceVal(12,p,q,SurfSideID)
                    tmpForceZ   = MacroSurfaceVal(13,p,q,SurfSideID)
                END IF
                tmpForce    = SQRT(tmpForceX**2 + tmpForceY**2 + tmpForceZ**2)

                partForce(iBC) = partForce(iBC) + tmpForce
                ! Max impact force
                maxForce(iBC)  = MAX(maxForce(iBC),tmpForce)
                
            ELSE
                nShift    = Species_opt * (nErosionVars-1)
                nShiftRHS = Species_opt * nErosionVars
                ! Only consider walls with actual impacts
                IF (MacroSurfaceVal(1+nShift,p,q,SurfSideID).EQ.0) CYCLE
                ! Average kinetic energy
                SideImpacts(iBC)=SideImpacts(iBC) + SampWall(SurfSideID)%State(1+nShiftRHS,p,q)
                EkinMean(iBC)  = EkinMean(iBC)  * (SideImpacts(iBC)-SampWall(SurfSideID)%State(1+nShiftRHS,p,q))/SideImpacts(iBC)  &
                             +MacroSurfaceVal(3+nShift,p,q,SurfSideID)*SampWall(SurfSideID)%State(1+nShiftRHS,p,q) /SideImpacts(iBC)
                EkinVar(iBC)   = EkinVar(iBC)   * (SideImpacts(iBC)-SampWall(SurfSideID)%State(1+nShiftRHS,p,q))/SideImpacts(iBC)  &
                             +MacroSurfaceVal(6+nShift,p,q,SurfSideID)*SampWall(SurfSideID)%State(1+nShiftRHS,p,q) /SideImpacts(iBC)
                ! Average impact angle
                AlphaMean(iBC) = AlphaMean(iBC)* (SideImpacts(iBC)-SampWall(SurfSideID)%State(1+nShiftRHS,p,q))/SideImpacts(iBC)   &
                            +MacroSurfaceVal(7+nShift,p,q,SurfSideID)*SampWall(SurfSideID)%State(1+nShiftRHS,p,q) /SideImpacts(iBC)
                AlphaVar(iBC)  = AlphaVar(iBC) * (SideImpacts(iBC)-SampWall(SurfSideID)%State(1+nShiftRHS,p,q))/SideImpacts(iBC)   &
                            +MacroSurfaceVal(10+nShift,p,q,SurfSideID)*SampWall(SurfSideID)%State(1+nShiftRHS,p,q) /SideImpacts(iBC)
                ! Integrated impact force
                IF (.NOT.ALMOSTZERO(TimeSample)) THEN
                    tmpForceX   = MacroSurfaceVal(11+nShift,p,q,SurfSideID)
                    tmpForceY   = MacroSurfaceVal(12+nShift,p,q,SurfSideID)
                    tmpForceZ   = MacroSurfaceVal(13+nShift,p,q,SurfSideID)
                END IF
                tmpForce    = SQRT(tmpForceX**2 + tmpForceY**2 + tmpForceZ**2)

                partForce(iBC) = partForce(iBC) + tmpForce
                ! Max impact force
                maxForce(iBC)  = MAX(maxForce(iBC),tmpForce)

                SideImpacts(iBC)  = SideImpacts(iBC) + SampWall(SurfSideID)%State(1,p,q)
            END IF
        END DO
    END DO
END DO

#if USE_MPI
IF(MPIRoot)THEN
  CALL MPI_REDUCE(MPI_IN_PLACE,EkinMean ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,EkinVar  ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,AlphaMean,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,AlphaVar ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,partForce,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,maxForce ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(MPI_IN_PLACE,SideImpacts,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
ELSE
  CALL MPI_REDUCE(EkinMean        ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(EkinVar         ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(AlphaMean       ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(AlphaVar        ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(partForce       ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(maxForce        ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
  CALL MPI_REDUCE(SideImpacts     ,0    ,nBCs,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,iError)
END IF
#endif

DO iBC=1,nBCs
    IF(.NOT.isWall(iBC)) CYCLE
    IF(ALMOSTZERO(SideArea(iBC))) CYCLE
    EkinMean(iBC)  = EkinMean(iBC)  / SideImpacts(iBC)
    EkinVar(iBC)   = EkinVar(iBC)   / SideImpacts(iBC)
    AlphaMean(iBC) = AlphaMean(iBC) / SideImpacts(iBC)
    AlphaVar(iBC)  = AlphaVar(iBC)  / SideImpacts(iBC)
END DO
CASE DEFAULT
     CALL abort(&
__STAMP__&
         ,'Posti numerical integration method unknown or not given.')
END SELECT

END SUBROUTINE CalcWallParticles

END MODULE MOD_Posti_CalcWallParticles