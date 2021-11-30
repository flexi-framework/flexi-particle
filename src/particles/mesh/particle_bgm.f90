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
#include "flexi.h"
#include "particle.h"

MODULE MOD_Particle_BGM
!===================================================================================================================================
!> Contains
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE DefineParametersParticleBGM
    MODULE PROCEDURE DefineParametersParticleBGM
END INTERFACE

INTERFACE BuildBGMAndIdentifyHaloRegion
    MODULE PROCEDURE BuildBGMAndIdentifyHaloRegion
END INTERFACE

INTERFACE FinalizeBGM
    MODULE PROCEDURE FinalizeBGM
END INTERFACE

#if USE_MPI
INTERFACE WriteHaloInfo
  MODULE PROCEDURE WriteHaloInfo
END INTERFACE

INTERFACE FinalizeHaloInfo
  MODULE PROCEDURE FinalizeHaloInfo
END INTERFACE
#endif /*USE_MPI*/

PUBLIC :: DefineParametersParticleBGM
PUBLIC :: BuildBGMAndIdentifyHaloRegion
PUBLIC :: FinalizeBGM
#if USE_MPI
PUBLIC :: WriteHaloInfo
PUBLIC :: FinalizeHaloInfo
#endif /*USE_MPI*/

CONTAINS

!==================================================================================================================================
!> Define parameters for particle backgroundmesh
!==================================================================================================================================
SUBROUTINE DefineParametersParticleBGM()
! MODULES
USE MOD_Globals
USE MOD_ReadInTools ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection('BGM')

! Background mesh init variables
CALL prms%CreateRealArrayOption('Part-FIBGMdeltas'&
  , 'Define the deltas for the Cartesian Fast-Init-Background-Mesh.'//&
  ' They should be of the similar size as the smallest cells of the used mesh for simulation.'&
  , '1. , 1. , 1.')
CALL prms%CreateRealArrayOption('Part-FactorFIBGM'&
  , 'Factor with which the background mesh will be scaled.'&
  , '1. , 1. , 1.')

END SUBROUTINE DefineParametersParticleBGM


SUBROUTINE BuildBGMAndIdentifyHaloRegion()
!===================================================================================================================================
!> computes the BGM-indices of an element and maps the number of element and which element to each BGM cell
!> BGM is only saved for compute-node-mesh + halo-region on shared memory
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Preproc
USE MOD_CalcTimeStep           ,ONLY: CalcTimeStep
USE MOD_DG                     ,ONLY: DGTimeDerivative_weakForm
USE MOD_Mesh_Vars              ,ONLY: nElems,offsetElem
USE MOD_Particle_Globals       ,ONLY: VECNORM
USE MOD_Particle_Periodic_BC   ,ONLY: InitPeriodicBC
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemInfo_Shared,NodeCoords_Shared
USE MOD_Particle_Mesh_Vars     ,ONLY: BoundsOfElem_Shared
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemToBGM_Shared
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_nElems
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_Element
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_offsetElem
USE MOD_Particle_Mesh_Tools    ,ONLY: GetGlobalNonUniqueSideID
USE MOD_Particle_Surfaces_Vars ,ONLY: BezierControlPoints3D
USE MOD_Particle_TimeDisc_Vars ,ONLY: PreviousTime
USE MOD_Particle_Tracking_Vars ,ONLY: TrackingMethod,Distance,ListDistance
USE MOD_ReadInTools            ,ONLY: GETREAL,GetRealArray
USE MOD_TimeDisc_Vars          ,ONLY: dt,t
USE MOD_Particle_Timedisc_Vars ,ONLY: ManualTimeStep
#if USE_MPI
USE MOD_Mesh_Vars              ,ONLY: nGlobalElems
USE MOD_Particle_Mesh_Vars     ,ONLY: nComputeNodeElems,offsetComputeNodeElem,nComputeNodeSides,nNonUniqueGlobalSides,nNonUniqueGlobalNodes
USE MOD_Particle_Mesh_Vars     ,ONLY: SideInfo_Shared,ElemInfo_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: BoundsOfElem_Shared_Win,ElemToBGM_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_nTotalElems,FIBGM_nTotalElems_Shared,FIBGM_nTotalElems_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGMToProcFlag,FIBGMToProcFlag_Shared,FIBGMToProcFlag_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_nElems_Shared,FIBGM_nElems_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_Element_Shared,FIBGM_Element_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_offsetElem_Shared,FIBGM_offsetElem_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGMToProc,FIBGMToProc_Shared,FIBGMToProc_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGMProcs,FIBGMProcs_Shared,FIBGMProcs_Shared_Win
USE MOD_Particle_Mesh_Vars     ,ONLY: MeshHasPeriodic
USE MOD_Particle_MPI_Vars      ,ONLY: SafetyFactor,halo_eps_velo,halo_eps,halo_eps2
USE MOD_Particle_MPI_Shared    ,ONLY: Allocate_Shared,MPI_SIZE,BARRIER_AND_SYNC
USE MOD_Particle_MPI_Shared_Vars
USE MOD_TimeDisc_Vars          ,ONLY: nRKStages,RKc
#endif /*USE_MPI*/
!----------------------------------------------------------------------------------------------------------------------------------!
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iElem,iLocSide,SideID
INTEGER                        :: FirstElem,LastElem
INTEGER                        :: firstNodeID,lastNodeID
INTEGER                        :: offsetNodeID,nNodeIDs,currentOffset
INTEGER,PARAMETER              :: moveBGMindex=1,increment=1,haloChange=3
REAL                           :: xmin,xmax,ymin,ymax,zmin,zmax
INTEGER                        :: iBGM,jBGM,kBGM
INTEGER                        :: BGMimax,BGMimin,BGMjmax,BGMjmin,BGMkmax,BGMkmin
INTEGER                        :: BGMCellXmax,BGMCellXmin,BGMCellYmax,BGMCellYmin,BGMCellZmax,BGMCellZmin
INTEGER                        :: BGMiminglob,BGMimaxglob,BGMjminglob,BGMjmaxglob,BGMkminglob,BGMkmaxglob
REAL                           :: deltaT
INTEGER                        :: errType
#if USE_MPI
INTEGER                        :: iStage
INTEGER                        :: iSide
INTEGER                        :: ElemID
REAL                           :: globalDiag,maxCellRadius
INTEGER,ALLOCATABLE            :: sendbuf(:,:,:),recvbuf(:,:,:)
INTEGER,ALLOCATABLE            :: offsetElemsInBGMCell(:,:,:)
INTEGER                        :: nHaloElems,nMPISidesShared
INTEGER,ALLOCATABLE            :: offsetCNHalo2GlobalElem(:),offsetMPISideShared(:)
REAL,ALLOCATABLE               :: BoundsOfElemCenter(:),MPISideBoundsOfElemCenter(:,:)
LOGICAL                        :: ElemInsideHalo
INTEGER                        :: firstHaloElem,lastHaloElem
! FIBGMToProc
LOGICAL                        :: dummyLog
INTEGER                        :: iProc,ProcRank,nFIBGMToProc,MessageSize,dummyInt
INTEGER                        :: BGMiDelta,BGMjDelta,BGMkDelta
INTEGER                        :: BGMiglobDelta,BGMjglobDelta,BGMkglobDelta
! Periodic FIBGM
LOGICAL                        :: PeriodicComponent(1:3)
INTEGER                        :: iPeriodicVector,iPeriodicComponent
! Mortar
INTEGER                        :: iMortar,NbElemID,NbSideID,nMortarElems
#else
REAL                           :: halo_eps
#endif /*USE_MPI*/
#if CODE_ANALYZE
INTEGER,ALLOCATABLE            :: NumberOfElements(:)
#endif /*CODE_ANALYZE*/
!===================================================================================================================================

! Read parameter for FastInitBackgroundMesh (FIBGM)
GEO%FIBGMdeltas(1:3) = GETREALARRAY('Part-FIBGMdeltas',3,'1. , 1. , 1.')
GEO%FactorFIBGM(1:3) = GETREALARRAY('Part-FactorFIBGM',3,'1. , 1. , 1.')
GEO%FIBGMdeltas(1:3) = 1./GEO%FactorFIBGM(1:3) * GEO%FIBGMdeltas(1:3)

! Ensure BGM does not protrude beyond mesh when divisible by FIBGMdeltas
BGMiminglob = 0 + moveBGMindex
BGMimaxglob = FLOOR((GEO%xmaxglob-GEO%xminglob)/GEO%FIBGMdeltas(1)) + moveBGMindex
BGMimaxglob = MERGE(BGMimaxglob,BGMimaxglob-1,MODULO(GEO%xmaxglob-GEO%xminglob,GEO%FIBGMdeltas(1)).NE.0)
BGMjminglob = 0 + moveBGMindex
BGMjmaxglob = FLOOR((GEO%ymaxglob-GEO%yminglob)/GEO%FIBGMdeltas(2)) + moveBGMindex
BGMjmaxglob = MERGE(BGMjmaxglob,BGMjmaxglob-1,MODULO(GEO%ymaxglob-GEO%yminglob,GEO%FIBGMdeltas(2)).NE.0)
BGMkminglob = 0 + moveBGMindex
BGMkmaxglob = FLOOR((GEO%zmaxglob-GEO%zminglob)/GEO%FIBGMdeltas(3)) + moveBGMindex
BGMkmaxglob = MERGE(BGMkmaxglob,BGMkmaxglob-1,MODULO(GEO%zmaxglob-GEO%zminglob,GEO%FIBGMdeltas(3)).NE.0)

GEO%FIBGMiminglob = BGMiminglob
GEO%FIBGMimaxglob = BGMimaxglob
GEO%FIBGMjminglob = BGMjminglob
GEO%FIBGMjmaxglob = BGMjmaxglob
GEO%FIBGMkminglob = BGMkminglob
GEO%FIBGMkmaxglob = BGMkmaxglob

! Read periodic vectors from parameter file
CALL InitPeriodicBC()

#if USE_MPI
CALL Allocate_Shared((/6,nGlobalElems/),ElemToBGM_Shared_Win,ElemToBGM_Shared)
CALL Allocate_Shared((/2,3,nGlobalElems/),BoundsOfElem_Shared_Win,BoundsOfElem_Shared)
CALL MPI_WIN_LOCK_ALL(0,ElemToBGM_Shared_Win,IERROR)
CALL MPI_WIN_LOCK_ALL(0,BoundsOfElem_Shared_Win,IERROR)
firstElem = INT(REAL( myComputeNodeRank   *nGlobalElems)/REAL(nComputeNodeProcessors))+1
lastElem  = INT(REAL((myComputeNodeRank+1)*nGlobalElems)/REAL(nComputeNodeProcessors))
! Periodic Sides
MeshHasPeriodic    = MERGE(.TRUE.,.FALSE.,GEO%nPeriodicVectors.GT.0)
#else
! In order to use only one type of variables VarName_Shared in code structure such as tracking etc. for NON_MPI
! the same variables are allocated on the single proc and used from mesh_vars instead of mpi_shared_vars
ALLOCATE(ElemToBGM_Shared(   1:6,    1:nElems))
ALLOCATE(BoundsOfElem_Shared(1:2,1:3,1:nElems)) ! 1-2: Min, Max value; 1-3: x,y,z
firstElem = 1
lastElem  = nElems
#endif  /*USE_MPI*/

! Use NodeCoords only for TriaTracking since Tracing and RefMapping have potentially curved elements, only BezierControlPoints form
! convec hull
SELECT CASE(TrackingMethod)
  CASE(TRIATRACKING)
    DO iElem = firstElem, lastElem
      offSetNodeID = ElemInfo_Shared(ELEM_FIRSTNODEIND,iElem)
      nNodeIDs     = ElemInfo_Shared(ELEM_LASTNODEIND ,iElem)-ElemInfo_Shared(ELEM_FIRSTNODEIND,iElem)
      firstNodeID  = offsetNodeID+1
      lastNodeID   = offsetNodeID+nNodeIDs

      xmin=MINVAL(NodeCoords_Shared(1,firstNodeID:lastNodeID))
      xmax=MAXVAL(NodeCoords_Shared(1,firstNodeID:lastNodeID))
      ymin=MINVAL(NodeCoords_Shared(2,firstNodeID:lastNodeID))
      ymax=MAXVAL(NodeCoords_Shared(2,firstNodeID:lastNodeID))
      zmin=MINVAL(NodeCoords_Shared(3,firstNodeID:lastNodeID))
      zmax=MAXVAL(NodeCoords_Shared(3,firstNodeID:lastNodeID))

      BoundsOfElem_Shared(1,1,iElem) = xmin
      BoundsOfElem_Shared(2,1,iElem) = xmax
      BoundsOfElem_Shared(1,2,iElem) = ymin
      BoundsOfElem_Shared(2,2,iElem) = ymax
      BoundsOfElem_Shared(1,3,iElem) = zmin
      BoundsOfElem_Shared(2,3,iElem) = zmax

      ! BGM indices must be >0 --> move by 1
      ElemToBGM_Shared(1,iElem) = MAX(FLOOR((xmin-GEO%xminglob)/GEO%FIBGMdeltas(1)),0) + moveBGMindex
      ElemToBGM_Shared(2,iElem) = MIN(FLOOR((xmax-GEO%xminglob)/GEO%FIBGMdeltas(1))    + moveBGMindex,GEO%FIBGMimaxglob)
      ElemToBGM_Shared(3,iElem) = MAX(FLOOR((ymin-GEO%yminglob)/GEO%FIBGMdeltas(2)),0) + moveBGMindex
      ElemToBGM_Shared(4,iElem) = MIN(FLOOR((ymax-GEO%yminglob)/GEO%FIBGMdeltas(2))    + moveBGMindex,GEO%FIBGMjmaxglob)
      ElemToBGM_Shared(5,iElem) = MAX(FLOOR((zmin-GEO%zminglob)/GEO%FIBGMdeltas(3)),0) + moveBGMindex
      ElemToBGM_Shared(6,iElem) = MIN(FLOOR((zmax-GEO%zminglob)/GEO%FIBGMdeltas(3))    + moveBGMindex,GEO%FIBGMkmaxglob)
    END DO ! iElem = firstElem, lastElem

  CASE(TRACING,REFMAPPING)
    DO iElem = firstElem, lastElem
      xmin= HUGE(1.)
      xmax=-HUGE(1.)
      ymin= HUGE(1.)
      ymax=-HUGE(1.)
      zmin= HUGE(1.)
      zmax=-HUGE(1.)

      DO iLocSide = 1,6
        SideID = GetGlobalNonUniqueSideID(iElem,iLocSide)
        xmin = MIN(xmin,MINVAL(BezierControlPoints3D(1,:,:,SideID)))
        xmax = MAX(xmax,MAXVAL(BezierControlPoints3D(1,:,:,SideID)))
        ymin = MIN(ymin,MINVAL(BezierControlPoints3D(2,:,:,SideID)))
        ymax = MAX(ymax,MAXVAL(BezierControlPoints3D(2,:,:,SideID)))
        zmin = MIN(zmin,MINVAL(BezierControlPoints3D(3,:,:,SideID)))
        zmax = MAX(zmax,MAXVAL(BezierControlPoints3D(3,:,:,SideID)))
      END DO

      ! Restrict to domain extent
      xmin = MAX(xmin,GEO%xminglob)
      xmax = MIN(xmax,GEO%xmaxglob)
      ymin = MAX(ymin,GEO%yminglob)
      ymax = MIN(ymax,GEO%ymaxglob)
      zmin = MAX(zmin,GEO%zminglob)
      zmax = MIN(zmax,GEO%zmaxglob)

      BoundsOfElem_Shared(1,1,iElem) = xmin
      BoundsOfElem_Shared(2,1,iElem) = xmax
      BoundsOfElem_Shared(1,2,iElem) = ymin
      BoundsOfElem_Shared(2,2,iElem) = ymax
      BoundsOfElem_Shared(1,3,iElem) = zmin
      BoundsOfElem_Shared(2,3,iElem) = zmax

      ! BGM indices must be >0 --> move by 1
      ElemToBGM_Shared(1,iElem) = MAX(FLOOR((xmin-GEO%xminglob)/GEO%FIBGMdeltas(1)),0) + moveBGMindex
      ElemToBGM_Shared(2,iElem) = MIN(FLOOR((xmax-GEO%xminglob)/GEO%FIBGMdeltas(1))    + moveBGMindex,GEO%FIBGMimaxglob)
      ElemToBGM_Shared(3,iElem) = MAX(FLOOR((ymin-GEO%yminglob)/GEO%FIBGMdeltas(2)),0) + moveBGMindex
      ElemToBGM_Shared(4,iElem) = MIN(FLOOR((ymax-GEO%yminglob)/GEO%FIBGMdeltas(2))    + moveBGMindex,GEO%FIBGMjmaxglob)
      ElemToBGM_Shared(5,iElem) = MAX(FLOOR((zmin-GEO%zminglob)/GEO%FIBGMdeltas(3)),0) + moveBGMindex
      ElemToBGM_Shared(6,iElem) = MIN(FLOOR((zmax-GEO%zminglob)/GEO%FIBGMdeltas(3))    + moveBGMindex,GEO%FIBGMkmaxglob)
    END DO ! iElem = firstElem, lastElem
END SELECT

#if USE_MPI
CALL BARRIER_AND_SYNC(ElemToBGM_Shared_Win   ,MPI_COMM_SHARED)
CALL BARRIER_AND_SYNC(BoundsOfElem_Shared_Win,MPI_COMM_SHARED)
#endif  /*USE_MPI*/

! deallocate stuff // required for dynamic load balance
#if USE_LOADBALANCE
IF (ALLOCATED(GEO%FIBGM)) THEN
  DO iBGM=GEO%FIBGMimin,GEO%FIBGMimax
    DO jBGM=GEO%FIBGMjmin,GEO%FIBGMjmax
      DO kBGM=GEO%FIBGMkmin,GEO%FIBGMkmax
        SDEALLOCATE(GEO%FIBGM(iBGM,jBGM,kBGM)%Element)
      END DO ! kBGM
    END DO ! jBGM
  END DO ! iBGM
  DEALLOCATE(GEO%FIBGM)
END IF
#endif /*USE_LOADBALANCE*/

#if USE_MPI
SafetyFactor  = GETREAL('Part-SafetyFactor')
halo_eps_velo = GETREAL('Part-HaloEpsVelo')
#endif /*USE_MPI*/

! Calculate the time step
IF (ManualTimeStep.EQ.0.0) THEN
  ! Skip the call, otherwise particles get incremented twice
  PreviousTime = t
  ! WARNING: THIS CALL IS PERFORMED BEFORE THE INITIAL FV_SWITCH WITH INDSTARTTIME!
  CALL DGTimeDerivative_weakForm(t)
  PreviousTime = -1.
  ! Set the initial time step, so Particle_InitTimeDisc can set the correct b_dt
  deltaT = CalcTimeStep(errType)
  dt     = deltaT
ELSE
  deltaT = ManualTimeStep
  dt     = ManualTimeStep
END IF

#if USE_MPI
IF (nComputeNodeProcessors.EQ.nProcessors_Global) THEN
#endif /*USE_MPI*/
  halo_eps  = 0.
#if USE_MPI
  halo_eps2 = 0.
ELSE
  IF (halo_eps_velo.EQ.0) halo_eps_velo = 343 ! speed of sound
  halo_eps = RKc(2)
  DO iStage=2,nRKStages-1
    halo_eps = MAX(halo_eps,RKc(iStage+1)-RKc(iStage))
  END DO
  halo_eps = MAX(halo_eps,1.-RKc(nRKStages))
  SWRITE(UNIT_stdOut,'(A,E24.12)') ' | Max. RK dtFrac, calculated      ', halo_eps
  !dt multiplied with maximum RKdtFrac
  halo_eps = halo_eps*halo_eps_velo*deltaT*SafetyFactor

  ! limit halo_eps to diagonal of bounding box
  globalDiag = SQRT( (GEO%xmaxglob-GEO%xminglob)**2 &
                   + (GEO%ymaxglob-GEO%yminglob)**2 &
                   + (GEO%zmaxglob-GEO%zminglob)**2 )
  IF(halo_eps.GT.globalDiag)THEN
    SWRITE(UNIT_stdOut,'(A,E24.12)') ' | unlimited halo distance       ', halo_eps
    SWRITE(UNIT_stdOut,'(A       )') ' | limitation of halo distance'
    halo_eps=globalDiag
  END IF

  halo_eps2=halo_eps*halo_eps
  SWRITE(UNIT_stdOut,'(A,E24.12)') ' | halo distance                   ', halo_eps
  IF(halo_eps.LT.0.)CALL ABORT(__STAMP__,'halo_eps cannot be negative!')
END IF

! The initial cutoff is performed based on the FIBGM elements. However, we have to ensure that all possible halo elements, i.e.
! those in range (myRadius + otherRadius + halo_eps) will be tested. We make a worst case approximation by determining the
! global largest cell radius and use it to keep all cells that are in this range.
! >> Find radius of largest cell
maxCellRadius = 0
DO iElem = firstElem, lastElem
  maxCellRadius = MAX(maxCellRadius,VECNORM((/ BoundsOfElem_Shared(2,1,iElem)-BoundsOfElem_Shared(1,1,iElem), &
                                               BoundsOfElem_Shared(2,2,iElem)-BoundsOfElem_Shared(1,2,iElem), &
                                               BoundsOfElem_Shared(2,3,iElem)-BoundsOfElem_Shared(1,3,iElem)/)/2.))
END DO
! >> Communicate global maximum
CALL MPI_ALLREDUCE(MPI_IN_PLACE,maxCellRadius,1,MPI_DOUBLE_PRECISION,MPI_MAX,MPI_COMM_SHARED,iError)
SWRITE(UNIT_stdOut,'(A,E15.7,A)') ' | Found max. cell radius as', maxCellRadius, ', for building halo BGM ...'

! ! enlarge BGM with halo region (all element outside of this region will be cut off)
IF (GEO%nPeriodicVectors.GT.0 .AND. TrackingMethod.EQ.REFMAPPING) THEN
  PeriodicComponent = .FALSE.
  Do iPeriodicVector = 1,GEO%nPeriodicVectors
    DO iPeriodicComponent = 1,3
      IF (ABS(GEO%PeriodicVectors(iPeriodicComponent,iPeriodicVector)).GT.0) PeriodicComponent(iPeriodicComponent) = .TRUE.
    END DO
  END DO

  ! >> Take global maxima of cell radius into account and increase the considered range accordingly
  BGMimin = MERGE(GEO%FIBGMiminglob,MAX(FLOOR((GEO%CNxmin-(halo_eps+maxCellRadius)-GEO%xminglob)/GEO%FIBGMdeltas(1)),0) + moveBGMindex                   ,PeriodicComponent(1))
  BGMimax = MERGE(GEO%FIBGMimaxglob,MIN(FLOOR((GEO%CNxmax+(halo_eps+maxCellRadius)-GEO%xminglob)/GEO%FIBGMdeltas(1))    + moveBGMindex,GEO%FIBGMimaxglob),PeriodicComponent(1))
  BGMjmin = MERGE(GEO%FIBGMjminglob,MAX(FLOOR((GEO%CNymin-(halo_eps+maxCellRadius)-GEO%yminglob)/GEO%FIBGMdeltas(2)),0) + moveBGMindex                   ,PeriodicComponent(2))
  BGMjmax = MERGE(GEO%FIBGMjmaxglob,MIN(FLOOR((GEO%CNymax+(halo_eps+maxCellRadius)-GEO%yminglob)/GEO%FIBGMdeltas(2))    + moveBGMindex,GEO%FIBGMjmaxglob),PeriodicComponent(2))
  BGMkmin = MERGE(GEO%FIBGMkminglob,MAX(FLOOR((GEO%CNzmin-(halo_eps+maxCellRadius)-GEO%zminglob)/GEO%FIBGMdeltas(3)),0) + moveBGMindex                   ,PeriodicComponent(3))
  BGMkmax = MERGE(GEO%FIBGMkmaxglob,MIN(FLOOR((GEO%CNzmax+(halo_eps+maxCellRadius)-GEO%zminglob)/GEO%FIBGMdeltas(3))    + moveBGMindex,GEO%FIBGMkmaxglob),PeriodicComponent(3))
ELSE
  ! >> Take global maxima of cell radius into account and increase the considered range accordingly
  BGMimin = MAX(FLOOR((GEO%CNxmin-(halo_eps+maxCellRadius)-GEO%xminglob)/GEO%FIBGMdeltas(1)),0) + moveBGMindex
  BGMimax = MIN(FLOOR((GEO%CNxmax+(halo_eps+maxCellRadius)-GEO%xminglob)/GEO%FIBGMdeltas(1))    + moveBGMindex,GEO%FIBGMimaxglob)
  BGMjmin = MAX(FLOOR((GEO%CNymin-(halo_eps+maxCellRadius)-GEO%yminglob)/GEO%FIBGMdeltas(2)),0) + moveBGMindex
  BGMjmax = MIN(FLOOR((GEO%CNymax+(halo_eps+maxCellRadius)-GEO%yminglob)/GEO%FIBGMdeltas(2))    + moveBGMindex,GEO%FIBGMjmaxglob)
  BGMkmin = MAX(FLOOR((GEO%CNzmin-(halo_eps+maxCellRadius)-GEO%zminglob)/GEO%FIBGMdeltas(3)),0) + moveBGMindex
  BGMkmax = MIN(FLOOR((GEO%CNzmax+(halo_eps+maxCellRadius)-GEO%zminglob)/GEO%FIBGMdeltas(3))    + moveBGMindex,GEO%FIBGMkmaxglob)
END IF

! write function-local BGM indices into global variables
GEO%FIBGMimin = BGMimin
GEO%FIBGMimax = BGMimax
GEO%FIBGMjmin = BGMjmin
GEO%FIBGMjmax = BGMjmax
GEO%FIBGMkmin = BGMkmin
GEO%FIBGMkmax = BGMkmax
#else
BGMimin = BGMiminglob
BGMimax = BGMimaxglob
BGMjmin = BGMjminglob
BGMjmax = BGMjmaxglob
BGMkmin = BGMkminglob
BGMkmax = BGMkmaxglob

GEO%FIBGMimin = BGMimin
GEO%FIBGMimax = BGMimax
GEO%FIBGMjmin = BGMjmin
GEO%FIBGMjmax = BGMjmax
GEO%FIBGMkmin = BGMkmin
GEO%FIBGMkmax = BGMkmax
#endif /*USE_MPI*/

ALLOCATE(GEO%FIBGM(BGMimin:BGMimax,BGMjmin:BGMjmax,BGMkmin:BGMkmax))

! null number of element per BGM cell
DO kBGM = BGMkmin,BGMkmax
  DO jBGM = BGMjmin,BGMjmax
    DO iBGM = BGMimin,BGMimax
      GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = 0
    END DO ! kBGM
  END DO ! jBGM
END DO ! iBGM

#if USE_MPI
! check which element is inside of compute-node domain (1),
! check which element is inside of compute-node halo (2)
! and which element is outside of compute-node domain (0)
! first do coarse check with BGM
IF (nComputeNodeProcessors.EQ.nProcessors_Global) THEN
  ElemInfo_Shared(ELEM_HALOFLAG,firstElem:lastElem) = 1
  ! initial values to eliminate compiler warnings
  firstHaloElem = -1
  lastHaloElem  = -1
ELSE
  ElemInfo_Shared(ELEM_HALOFLAG,firstElem:lastElem) = 0
  DO iElem = firstElem, lastElem
    BGMCellXmin = ElemToBGM_Shared(1,iElem)
    BGMCellXmax = ElemToBGM_Shared(2,iElem)
    BGMCellYmin = ElemToBGM_Shared(3,iElem)
    BGMCellYmax = ElemToBGM_Shared(4,iElem)
    BGMCellZmin = ElemToBGM_Shared(5,iElem)
    BGMCellZmax = ElemToBGM_Shared(6,iElem)
    ! add current element to number of BGM-elems
    ! ATTENTION: THIS ONLY ADDS THE ELEMENT TO THE BGM CELLS ON THE NODE WHILE
    ! SKIPPING BGM CELLS OUTSIDE. WE END UP WITH PARTIALLY ADDED ELEMENTS
    DO iBGM = BGMCellXmin,BGMCellXmax
      IF(iBGM.LT.BGMimin) CYCLE
      IF(iBGM.GT.BGMimax) CYCLE
      DO jBGM = BGMCellYmin,BGMCellYmax
        IF(jBGM.LT.BGMjmin) CYCLE
        IF(jBGM.GT.BGMjmax) CYCLE
        DO kBGM = BGMCellZmin,BGMCellZmax
          IF(kBGM.LT.BGMkmin) CYCLE
          IF(kBGM.GT.BGMkmax) CYCLE
          !GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem + 1
          IF (iElem.GE.offsetComputeNodeElem+1 .AND. iElem.LE.offsetComputeNodeElem+nComputeNodeElems) THEN
            ElemInfo_Shared(ELEM_HALOFLAG,iElem) = 1 ! compute-node element
          ELSE
            ElemInfo_Shared(ELEM_HALOFLAG,iElem) = 2 ! halo element
          END IF
        END DO ! kBGM
      END DO ! jBGM
    END DO ! iBGM
  END DO ! iElem
  CALL BARRIER_AND_SYNC(ElemInfo_Shared_Win,MPI_COMM_SHARED)

  ! sum up potential halo elements and create correct offset mapping via ElemInfo_Shared
  nHaloElems = COUNT(ElemInfo_Shared(ELEM_HALOFLAG,:).EQ.2)

  ALLOCATE(offsetCNHalo2GlobalElem(1:nHaloElems))
  offsetCNHalo2GlobalElem = -1
  nHaloElems = 0
  DO iElem = 1, nGlobalElems
    IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).EQ.2) THEN
      nHaloElems = nHaloElems + 1
      offsetCNHalo2GlobalElem(nHaloElems) = iElem
    END IF
  END DO
  ! The code below changes ElemInfo_Shared, identification of halo elements must complete before
  CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)

  ! sum all MPI-side of compute-node and create correct offset mapping in SideInfo_Shared
  nMPISidesShared = COUNT(SideInfo_Shared(SIDE_NBELEMTYPE,:).EQ.2)
  ALLOCATE(offsetMPISideShared(nMPISidesShared))

  nMPISidesShared = 0
  DO iSide = 1, nNonUniqueGlobalSides
    IF (SideInfo_Shared(SIDE_NBELEMTYPE,iSide).EQ.2) THEN
      nMPISidesShared = nMPISidesShared + 1
      offsetMPISideShared(nMPISidesShared) = iSide
    END IF
  END DO

  ! Distribute nHaloElements evenly on compute-node procs
  IF (nHaloElems.GT.nComputeNodeProcessors) THEN
    firstHaloElem = INT(REAL( myComputeNodeRank   *nHaloElems)/REAL(nComputeNodeProcessors))+1
    lastHaloElem  = INT(REAL((myComputeNodeRank+1)*nHaloElems)/REAL(nComputeNodeProcessors))
  ELSE
    firstHaloElem = myComputeNodeRank + 1
    IF (myComputeNodeRank.LT.nHaloElems) THEN
      lastHaloElem = myComputeNodeRank + 1
    ELSE
      lastHaloElem = 0
    END IF
  END IF

  ! Get centers and radii of all CN elements connected to MPI sides for distance check with the halo elements assigned to the proc
  ALLOCATE(MPISideBoundsOfElemCenter(1:4,1:nMPISidesShared))
  DO iSide = 1, nMPISidesShared
    SideID = offsetMPISideShared(iSide)
    ElemID = SideInfo_Shared(SIDE_ELEMID,SideID)
    MPISideBoundsOfElemCenter(1:3,iSide) = (/    SUM(BoundsOfElem_Shared(1:2,1,ElemID)), &
                                                 SUM(BoundsOfElem_Shared(1:2,2,ElemID)), &
                                                 SUM(BoundsOfElem_Shared(1:2,3,ElemID)) /) / 2.
    ! Calculate outer radius of the element on my compute node
    MPISideBoundsOfElemCenter(4,iSide) = VECNORM ((/ BoundsOfElem_Shared(2  ,1,ElemID)-BoundsOfElem_Shared(1,1,ElemID), &
                                                     BoundsOfElem_Shared(2  ,2,ElemID)-BoundsOfElem_Shared(1,2,ElemID), &
                                                     BoundsOfElem_Shared(2  ,3,ElemID)-BoundsOfElem_Shared(1,3,ElemID) /) / 2.)
  END DO

  ! do refined check: (refined halo region reduction)
  ! check the bounding box of each element in compute-nodes' halo domain
  ! against the bounding boxes of the elements of the MPI-surface (inter compute-node MPI sides)
  ALLOCATE(BoundsOfElemCenter(1:4))
  DO iElem = firstHaloElem,lastHaloElem
    ElemID = offsetCNHalo2GlobalElem(iElem)
    ElemInsideHalo = .FALSE.
    BoundsOfElemCenter(1:3) = (/    SUM(BoundsOfElem_Shared(1:2,1,ElemID)), &
                                    SUM(BoundsOfElem_Shared(1:2,2,ElemID)), &
                                    SUM(BoundsOfElem_Shared(1:2,3,ElemID)) /) / 2.
    ! Calculate halo element outer radius
    BoundsOfElemCenter(4) = VECNORM ((/ BoundsOfElem_Shared(2  ,1,ElemID)-BoundsOfElem_Shared(1,1,ElemID), &
                                        BoundsOfElem_Shared(2  ,2,ElemID)-BoundsOfElem_Shared(1,2,ElemID), &
                                        BoundsOfElem_Shared(2  ,3,ElemID)-BoundsOfElem_Shared(1,3,ElemID) /) / 2.)
    DO iSide = 1, nMPISidesShared
      ! compare distance of centers with sum of element outer radii+halo_eps
      IF (VECNORM(BoundsOfElemCenter(1:3)-MPISideBoundsOfElemCenter(1:3,iSide)) &
          .GT. halo_eps+BoundsOfElemCenter(4)+MPISideBoundsOfElemCenter(4,iSide) ) CYCLE
      ElemInsideHalo = .TRUE.
      EXIT
    END DO ! iSide = 1, nMPISidesShared
    IF (.NOT.ElemInsideHalo) THEN
      ElemInfo_Shared(ELEM_HALOFLAG,ElemID) = 0
    ELSE
      ! Only add element to BGM if inside halo region on node.
      ! THIS IS WRONG. WE ARE WORKING ON THE CN HALO REGION. IF WE OMIT THE
      ! ELEMENT HERE, WE LOOSE IT. IF WE KEEP IT, WE BREAK AT 589. YOUR CALL.
      CALL AddElementToFIBGM(ElemID)
    END IF
  END DO ! iElem = firstHaloElem, lastHaloElem
END IF ! nComputeNodeProcessors.EQ.nProcessors_Global
CALL BARRIER_AND_SYNC(ElemInfo_Shared_Win            ,MPI_COMM_SHARED)

IF (MeshHasPeriodic)    CALL CheckPeriodicSides()
CALL BARRIER_AND_SYNC(ElemInfo_Shared_Win,MPI_COMM_SHARED)

! Mortar sides
IF (nComputeNodeProcessors.NE.nProcessors_Global) THEN
  DO iElem = firstElem, lastElem
    IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).LT.1) CYCLE

    ! Loop over all sides and check for mortar sides
    DO iSide = ElemInfo_Shared(ELEM_FIRSTSIDEIND,iElem)+1,ElemInfo_Shared(ELEM_LASTSIDEIND,iElem)
      NbElemID = SideInfo_Shared(SIDE_NBELEMID,iSide)
      ! Mortar side
      IF (NbElemID.LT.0) THEN
        nMortarElems = MERGE(4,2,SideInfo_Shared(SIDE_NBELEMID,iSide).EQ.-1)

        DO iMortar = 1,nMortarElems
          NbSideID   = SideInfo_Shared(SIDE_NBSIDEID,iSide + iMortar)
          ElemID     = SideInfo_Shared(SIDE_ELEMID  ,NbSideID)

          ! Element not previously flagged
          IF (ElemInfo_Shared(ELEM_HALOFLAG,ElemID).LT.1) THEN
            ASSOCIATE(posElem => (ElemID-1)*ELEMINFOSIZE + (ELEM_HALOFLAG-1))
              CALL MPI_FETCH_AND_OP(haloChange,dummyInt,MPI_INTEGER,0,INT(posElem*SIZE_INT,MPI_ADDRESS_KIND),MPI_REPLACE,ElemInfo_Shared_Win,IERROR)
            END ASSOCIATE
          END IF
        END DO
      END IF
    END DO
  END DO
END IF

CALL BARRIER_AND_SYNC(ElemInfo_Shared_Win,MPI_COMM_SHARED)
#else
ElemInfo_Shared(ELEM_HALOFLAG,:) = 1
#endif  /*USE_MPI*/

!--- compute number of elements in each background cell
DO iElem = offsetElem+1, offsetElem+nElems
  BGMCellXmin = ElemToBGM_Shared(1,iElem)
  BGMCellXmax = ElemToBGM_Shared(2,iElem)
  BGMCellYmin = ElemToBGM_Shared(3,iElem)
  BGMCellYmax = ElemToBGM_Shared(4,iElem)
  BGMCellZmin = ElemToBGM_Shared(5,iElem)
  BGMCellZmax = ElemToBGM_Shared(6,iElem)
  ! add current element to number of BGM-elems
  DO iBGM = BGMCellXmin,BGMCellXmax
    DO jBGM = BGMCellYmin,BGMCellYmax
      DO kBGM = BGMCellZmin,BGMCellZmax
        GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem + 1
      END DO ! kBGM
    END DO ! jBGM
  END DO ! iBGM
END DO ! iElem

! alternative nElem count with cycles
!DO iElem = firstElem, lastElem
!  IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).EQ.0) CYCLE
!  BGMCellXmin = ElemToBGM_Shared(1,iElem)
!  BGMCellXmax = ElemToBGM_Shared(2,iElem)
!  BGMCellYmin = ElemToBGM_Shared(3,iElem)
!  BGMCellYmax = ElemToBGM_Shared(4,iElem)
!  BGMCellZmin = ElemToBGM_Shared(5,iElem)
!  BGMCellZmax = ElemToBGM_Shared(6,iElem)
!  ! add current element to number of BGM-elems
!  DO iBGM = BGMCellXmin,BGMCellXmax
!    DO jBGM = BGMCellYmin,BGMCellYmax
!      DO kBGM = BGMCellZmin,BGMCellZmax
!        GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem + 1
!      END DO ! kBGM
!    END DO ! jBGM
!  END DO ! iBGM
!END DO ! iElem

#if USE_MPI
ALLOCATE(sendbuf(BGMimin:BGMimax,BGMjmin:BGMjmax,BGMkmin:BGMkmax))
ALLOCATE(recvbuf(BGMimin:BGMimax,BGMjmin:BGMjmax,BGMkmin:BGMkmax))
! find max nelems and offset in each BGM cell
DO iBGM = BGMimin,BGMimax
  DO jBGM = BGMjmin,BGMjmax
    DO kBGM = BGMkmin,BGMkmax
      sendbuf(iBGM,jBGM,kBGM) = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem
      recvbuf(iBGM,jBGM,kBGM) = 0
    END DO ! kBGM
  END DO ! jBGM
END DO ! iBGM

BGMiDelta = BGMimax - BGMimin
BGMjDelta = BGMjmax - BGMjmin
BGMkDelta = BGMkmax - BGMkmin
! allocated shared memory for nElems per BGM cell
! MPI shared memory is continuous, beginning from 1. All shared arrays have to
! be shifted to BGM[i]min with pointers
ALLOCATE(offsetElemsInBGMCell(BGMimin:BGMimax,BGMjmin:BGMjmax,BGMkmin:BGMkmax))
CALL MPI_EXSCAN(sendbuf(:,:,:),recvbuf(:,:,:),(BGMiDelta+1)*(BGMjDelta+1)*(BGMkDelta+1),MPI_INTEGER,MPI_SUM,MPI_COMM_SHARED,iError)
offsetElemsInBGMCell = recvbuf
DEALLOCATE(recvbuf)

! last proc of compute-node calculates total number of elements in each BGM-cell
! after this loop sendbuf of last proc contains nElems per BGM cell
IF (myComputeNodeRank.EQ.nComputeNodeProcessors-1) THEN
  DO iBGM = BGMimin,BGMimax
    DO jBGM = BGMjmin,BGMjmax
      DO kBGM = BGMkmin,BGMkmax
        sendbuf(iBGM,jBGM,kBGM) = offsetElemsInBGMCell(iBGM,jBGM,kBGM) + GEO%FIBGM(iBGM,jBGM,kBGM)%nElem
      END DO ! kBGM
    END DO ! jBGM
  END DO ! iBGM
END IF

! allocated shared memory for nElems per BGM cell
! MPI shared memory is continuous, beginning from 1. All shared arrays have to
! be shifted to BGM[i]min with pointers
CALL Allocate_Shared((/(BGMiDelta+1)*(BGMjDelta+1)*(BGMkDelta+1)/) &
                    ,FIBGM_nElems_Shared_Win,FIBGM_nElems_Shared)
CALL MPI_WIN_LOCK_ALL(0,FIBGM_nElems_Shared_Win,IERROR)
! allocated shared memory for BGM cell offset in 1D array of BGM to element mapping
CALL Allocate_Shared((/(BGMiDelta+1)*(BGMjDelta+1)*(BGMkDelta+1)/) &
                    ,FIBGM_offsetElem_Shared_Win,FIBGM_offsetElem_Shared)
CALL MPI_WIN_LOCK_ALL(0,FIBGM_offsetElem_Shared_Win,IERROR)
FIBGM_nElems     (BGMimin:BGMimax,BGMjmin:BGMjmax,BGMkmin:BGMkmax) => FIBGM_nElems_Shared
FIBGM_offsetElem (BGMimin:BGMimax,BGMjmin:BGMjmax,BGMkmin:BGMkmax) => FIBGM_offsetElem_Shared

! last proc of compute-node writes into shared memory to make nElems per BGM accessible for every proc
IF (myComputeNodeRank.EQ.nComputeNodeProcessors-1) THEN
  currentOffset = 0
  DO iBGM = BGMimin,BGMimax
    DO jBGM = BGMjmin,BGMjmax
      DO kBGM = BGMkmin,BGMkmax
        ! senfbuf and recvbuf have to stay on original position. Shift 1 --> BGMimin
        FIBGM_nElems(iBGM,jBGM,kBGM)     = sendbuf(iBGM,jBGM,kBGM)
        FIBGM_offsetElem(iBGM,jBGM,kBGM) = currentOffset
        currentOffset = currentoffset    + sendbuf(iBGM,jBGM,kBGM)
      END DO ! kBGM
    END DO ! jBGM
  END DO ! iBGM
END IF
DEALLOCATE(sendbuf)
CALL BARRIER_AND_SYNC(FIBGM_nElems_Shared_Win    ,MPI_COMM_SHARED)
CALL BARRIER_AND_SYNC(FIBGM_offsetElem_Shared_Win,MPI_COMM_SHARED)
#else /*NOT USE_MPI*/
ALLOCATE(FIBGM_nElems    (BGMimin:BGMimax,BGMjmin:BGMjmax,BGMkmin:BGMkmax))
ALLOCATE(FIBGM_offsetElem(BGMimin:BGMimax,BGMjmin:BGMjmax,BGMkmin:BGMkmax))
currentOffset = 0
DO iBGM = BGMimin,BGMimax
  DO jBGM = BGMjmin,BGMjmax
    DO kBGM = BGMkmin,BGMkmax
      FIBGM_nElems(iBGM,jBGM,kBGM)     = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem
      FIBGM_offsetElem(iBGM,jBGM,kBGM) = currentOffset
      currentOffset = currentoffset    + GEO%FIBGM(iBGM,jBGM,kBGM)%nElem
    END DO ! kBGM
  END DO ! jBGM
END DO ! iBGM
#endif  /*USE_MPI*/

#if USE_MPI
! allocate 1D array for mapping of BGM cell to Element indeces
CALL Allocate_Shared((/FIBGM_offsetElem(BGMimax,BGMjmax,BGMkmax)   + &
                       FIBGM_nElems    (BGMimax,BGMjmax,BGMkmax)/)   &
                     ,FIBGM_Element_Shared_Win,FIBGM_Element_Shared)
CALL MPI_WIN_LOCK_ALL(0,FIBGM_Element_Shared_Win,IERROR)
FIBGM_Element => FIBGM_Element_Shared
#else
ALLOCATE( FIBGM_Element(1:FIBGM_offsetElem(BGMimax,BGMjmax,BGMkmax) + &
                          FIBGM_nElems    (BGMimax,BGMjmax,BGMkmax)))
#endif  /*USE_MPI*/

#if USE_MPI
IF (myComputeNodeRank.EQ.0) THEN
#endif /*USE_MPI*/
  FIBGM_Element = -1
#if USE_MPI
END IF
CALL BARRIER_AND_SYNC(FIBGM_Element_Shared_Win,MPI_COMM_SHARED)
#endif /*USE_MPI*/

DO iBGM = BGMimin,BGMimax
  DO jBGM = BGMjmin,BGMjmax
    DO kBGM = BGMkmin,BGMkmax
      GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = 0
    END DO ! kBGM
  END DO ! jBGM
END DO ! iBGM

#if USE_MPI
! We might need to expand the halo BGM region
IF (nComputeNodeProcessors.NE.nProcessors_Global) THEN
  DO iElem = firstHaloElem,lastHaloElem
    ElemID = offsetCNHalo2GlobalElem(iElem)

    ! Only add non-peri halo elems
    IF (ElemInfo_Shared(ELEM_HALOFLAG,ElemID).NE.2) CYCLE

    BGMCellXmin = MAX(ElemToBGM_Shared(1,ElemID),BGMimin)
    BGMCellXmax = MIN(ElemToBGM_Shared(2,ElemID),BGMimax)
    BGMCellYmin = MAX(ElemToBGM_Shared(3,ElemID),BGMjmin)
    BGMCellYmax = MIN(ElemToBGM_Shared(4,ElemID),BGMjmax)
    BGMCellZmin = MAX(ElemToBGM_Shared(5,ElemID),BGMkmin)
    BGMCellZmax = MIN(ElemToBGM_Shared(6,ElemID),BGMkmax)

    ! add current Element to BGM-Elem
    DO kBGM = BGMCellZmin,BGMCellZmax
      DO jBGM = BGMCellYmin,BGMCellYmax
        DO iBGM = BGMCellXmin,BGMCellXmax
          GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem + 1
          FIBGM_Element( FIBGM_offsetElem    (iBGM,jBGM,kBGM)        & ! offset of BGM cell in 1D array
                       + offsetElemsInBGMCell(iBGM,jBGM,kBGM)        & ! offset of BGM nElems in local proc
                       + GEO%FIBGM           (iBGM,jBGM,kBGM)%nElem) = ElemID
        END DO ! kBGM
      END DO ! jBGM
    END DO ! iBGM
  END DO ! iElem = firstHaloElem,lastHaloElem

  IF (TrackingMethod.EQ.REFMAPPING .AND. GEO%nPeriodicVectors.GT.0) THEN
    firstElem = INT(REAL( myComputeNodeRank   *nGlobalElems)/REAL(nComputeNodeProcessors))+1
    lastElem  = INT(REAL((myComputeNodeRank+1)*nGlobalElems)/REAL(nComputeNodeProcessors))
    DO ElemID = firstElem, lastElem
      ! Only add peri halo elems
      IF (ElemInfo_Shared(ELEM_HALOFLAG,ElemID).NE.3) CYCLE

      BGMCellXmin = MAX(ElemToBGM_Shared(1,ElemID),BGMimin)
      BGMCellXmax = MIN(ElemToBGM_Shared(2,ElemID),BGMimax)
      BGMCellYmin = MAX(ElemToBGM_Shared(3,ElemID),BGMjmin)
      BGMCellYmax = MIN(ElemToBGM_Shared(4,ElemID),BGMjmax)
      BGMCellZmin = MAX(ElemToBGM_Shared(5,ElemID),BGMkmin)
      BGMCellZmax = MIN(ElemToBGM_Shared(6,ElemID),BGMkmax)

      ! add current Element to BGM-Elem
      DO kBGM = BGMCellZmin,BGMCellZmax
        DO jBGM = BGMCellYmin,BGMCellYmax
          DO iBGM = BGMCellXmin,BGMCellXmax
            GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem + 1
            IF (FIBGM_Element( FIBGM_offsetElem    (iBGM,jBGM,kBGM)        & ! offset of BGM cell in 1D array
                         + offsetElemsInBGMCell(iBGM,jBGM,kBGM)        & ! offset of BGM nElems in local proc
                         + GEO%FIBGM           (iBGM,jBGM,kBGM)%nElem).NE.-1) CALL ABORT(__STAMP__,'Double access')
            FIBGM_Element( FIBGM_offsetElem    (iBGM,jBGM,kBGM)        & ! offset of BGM cell in 1D array
                         + offsetElemsInBGMCell(iBGM,jBGM,kBGM)        & ! offset of BGM nElems in local proc
                         + GEO%FIBGM           (iBGM,jBGM,kBGM)%nElem) = ElemID
          END DO ! kBGM
        END DO ! jBGM
      END DO ! iBGM
    END DO ! iElem = firstHaloElem, lastHaloElem
  END IF ! (TrackingMethod.EQ.REFMAPPING .AND. GEO%nPeriodicVectors.GT.0)
END IF
#endif  /*USE_MPI*/

! Add local elements
DO iElem = offsetElem+1, offsetElem+nElems
  ! find element extent on BGM
  BGMCellXmin = MAX(ElemToBGM_Shared(1,iElem),BGMimin)
  BGMCellXmax = MIN(ElemToBGM_Shared(2,iElem),BGMimax)
  BGMCellYmin = MAX(ElemToBGM_Shared(3,iElem),BGMjmin)
  BGMCellYmax = MIN(ElemToBGM_Shared(4,iElem),BGMjmax)
  BGMCellZmin = MAX(ElemToBGM_Shared(5,iElem),BGMkmin)
  BGMCellZmax = MIN(ElemToBGM_Shared(6,iElem),BGMkmax)

  ! add current element to BGM-Elem
  DO kBGM = BGMCellZmin,BGMCellZmax
    DO jBGM = BGMCellYmin,BGMCellYmax
      DO iBGM = BGMCellXmin,BGMCellXmax
        GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem + 1
        FIBGM_Element( FIBGM_offsetElem    (iBGM,jBGM,kBGM)        & ! offset of BGM cell in 1D array
#if USE_MPI
                     + offsetElemsInBGMCell(iBGM,jBGM,kBGM)        & ! offset of BGM nElems in local proc
#endif  /*USE_MPI*/
                     + GEO%FIBGM           (iBGM,jBGM,kBGM)%nElem) = iElem
      END DO ! kBGM
    END DO ! jBGM
  END DO ! iBGM
END DO ! iElem

!--- map elements to background cells
! alternative if nElem is counted with cycles
!DO iElem = firstElem, lastElem
!  IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).EQ.0) CYCLE
!  BGMCellXmin = ElemToBGM_Shared(1,iElem)
!  BGMCellXmax = ElemToBGM_Shared(2,iElem)
!  BGMCellYmin = ElemToBGM_Shared(3,iElem)
!  BGMCellYmax = ElemToBGM_Shared(4,iElem)
!  BGMCellZmin = ElemToBGM_Shared(5,iElem)
!  BGMCellZmax = ElemToBGM_Shared(6,iElem)
!  ! add current Element to BGM-Elem
!  DO kBGM = BGMCellZmin,BGMCellZmax
!    DO jBGM = BGMCellYmin,BGMCellYmax
!      DO iBGM = BGMCellXmin,BGMCellXmax
!        GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem + 1
!        FIBGM_Element( FIBGM_offsetElem(iBGM,jBGM,kBGM) & ! offset of BGM cell in 1D array
!#if USE_MPI
!                       + offsetElemsInBGMCell(iBGM,jBGM,kBGM)    & ! offset of BGM nElems in local proc
!#endif  /*USE_MPI*/
!                       + GEO%FIBGM(iBGM,jBGM,kBGM)%nElem         ) = iElem
!      END DO ! kBGM
!    END DO ! jBGM
!  END DO ! iBGM
!END DO ! iElem
#if USE_MPI
DEALLOCATE(offsetElemsInBGMCell)

CALL BARRIER_AND_SYNC(FIBGM_Element_Shared_Win,MPI_COMM_SHARED)

! Abort if FIBGM_Element still contains unfilled entries
IF (ANY(FIBGM_Element.EQ.-1)) CALL ABORT(__STAMP__,'Error while filling FIBGM element array')

! Locally sum up Number of all elements on current compute-node (including halo region)
IF (nComputeNodeProcessors.EQ.nProcessors_Global) THEN
  nComputeNodeTotalElems = nGlobalElems
  nComputeNodeTotalSides = nNonUniqueGlobalSides
  nComputeNodeTotalNodes = nNonUniqueGlobalNodes
ELSE
  nComputeNodeTotalElems = 0
  nComputeNodeTotalSides = 0
  nComputeNodeTotalNodes = 0
  DO iElem = 1, nGlobalElems
    IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).NE.0) THEN
      nComputeNodeTotalElems = nComputeNodeTotalElems + 1
    END IF
  END DO
  ALLOCATE(CNTotalElem2GlobalElem(1:nComputeNodeTotalElems))
  ALLOCATE(GlobalElem2CNTotalElem(1:nGlobalElems))
  nComputeNodeTotalElems = 0
  GlobalElem2CNTotalElem(1:nGlobalElems) = -1
  ! CN-local elements
  DO iElem = 1,nGlobalElems
    IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).EQ.1) THEN
      nComputeNodeTotalElems = nComputeNodeTotalElems + 1
      CNTotalElem2GlobalElem(nComputeNodeTotalElems) = iElem
      GlobalElem2CNTotalElem(iElem) = nComputeNodeTotalElems
      nComputeNodeTotalSides = nComputeNodeTotalSides &
                             + (ElemInfo_Shared(ELEM_LASTSIDEIND,iElem) - ElemInfo_Shared(ELEM_FIRSTSIDEIND,iElem))
      nComputeNodeTotalNodes = nComputeNodeTotalNodes &
                             + (ElemInfo_Shared(ELEM_LASTNODEIND,iElem) - ElemInfo_Shared(ELEM_FIRSTNODEIND,iElem))
    END IF
  END DO
  ! CN-halo elements (non-periodic)
  DO iElem = 1,nGlobalElems
    IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).EQ.2) THEN
      nComputeNodeTotalElems = nComputeNodeTotalElems + 1
      CNTotalElem2GlobalElem(nComputeNodeTotalElems) = iElem
      GlobalElem2CNTotalElem(iElem) = nComputeNodeTotalElems
      nComputeNodeTotalSides = nComputeNodeTotalSides &
                             + (ElemInfo_Shared(ELEM_LASTSIDEIND,iElem) - ElemInfo_Shared(ELEM_FIRSTSIDEIND,iElem))
      nComputeNodeTotalNodes = nComputeNodeTotalNodes &
                             + (ElemInfo_Shared(ELEM_LASTNODEIND,iElem) - ElemInfo_Shared(ELEM_FIRSTNODEIND,iElem))
    END IF
  END DO
  ! CN-halo elements (periodic)
  DO iElem = 1,nGlobalElems
    IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).EQ.3) THEN
      nComputeNodeTotalElems = nComputeNodeTotalElems + 1
      CNTotalElem2GlobalElem(nComputeNodeTotalElems) = iElem
      GlobalElem2CNTotalElem(iElem) = nComputeNodeTotalElems
      nComputeNodeTotalSides = nComputeNodeTotalSides &
                             + (ElemInfo_Shared(ELEM_LASTSIDEIND,iElem) - ElemInfo_Shared(ELEM_FIRSTSIDEIND,iElem))
      nComputeNodeTotalNodes = nComputeNodeTotalNodes &
                             + (ElemInfo_Shared(ELEM_LASTNODEIND,iElem) - ElemInfo_Shared(ELEM_FIRSTNODEIND,iElem))
    END IF
  END DO
END IF

#if CODE_ANALYZE
! Sanity checks
IF (  SUM(ElemInfo_Shared(ELEM_HALOFLAG,:)  ,MASK=ElemInfo_Shared(ELEM_HALOFLAG,:).EQ.1).NE.nComputeNodeElems) &
  CALL ABORT(__STAMP__,'Error with number of local elements on compute node')

IF ((SUM(ElemInfo_Shared(ELEM_HALOFLAG,:)  ,MASK=ElemInfo_Shared(ELEM_HALOFLAG,:).EQ.1) &
    +SUM(ElemInfo_Shared(ELEM_HALOFLAG,:)/2,MASK=ElemInfo_Shared(ELEM_HALOFLAG,:).EQ.2) &
    +SUM(ElemInfo_Shared(ELEM_HALOFLAG,:)/3,MASK=ElemInfo_Shared(ELEM_HALOFLAG,:).EQ.3)).NE.nComputeNodeTotalElems) &
  CALL ABORT(__STAMP__,'Error with number of halo elements on compute node')

! Debug output
IF (myRank.EQ.0) THEN
  SWRITE(UNIT_stdOut,'(A)') ' DETERMINED compute-node (CN) halo region ...'
  SWRITE(UNIT_stdOut,'(A)') ' | CN Rank | Local Elements | Halo Elements (non-peri) | Halo Elements (peri) |'
  CALL FLUSH(UNIT_stdOut)
  ALLOCATE(NumberOfElements(3*nLeaderGroupProcs))
END IF

IF (myComputeNodeRank.EQ.0) THEN
  ASSOCIATE( sendBuf => (/ &
        SUM(ElemInfo_Shared(ELEM_HALOFLAG,:)  ,MASK=ElemInfo_Shared(ELEM_HALOFLAG,:).EQ.1),  &
                     SUM(ElemInfo_Shared(ELEM_HALOFLAG,:)/2,MASK=ElemInfo_Shared(ELEM_HALOFLAG,:).EQ.2),  &
        SUM(ElemInfo_Shared(ELEM_HALOFLAG,:)/3,MASK=ElemInfo_Shared(ELEM_HALOFLAG,:).EQ.3)/) )
    IF (myRank.EQ.0) THEN
      CALL MPI_GATHER(sendBuf , 3 , MPI_INTEGER , NumberOfElements , 3 , MPI_INTEGER , 0 , MPI_COMM_LEADERS_SHARED , iError)
    ELSE
      CALL MPI_GATHER(sendBuf , 3 , MPI_INTEGER , MPI_IN_PLACE     , 3 , MPI_INTEGER , 0 , MPI_COMM_LEADERS_SHARED , iError)
    END IF
  END ASSOCIATE
END IF

IF (myRank.EQ.0) THEN
  DO iProc = 0,nLeaderGroupProcs-1
    WRITE(UNIT_stdOut,'(A,I7,A,I15,A,I25,A,I21,A)')  &
                                      ' |>',iProc, &
                                      ' |'  ,NumberOfElements(iProc*3+1), &
                                      ' |'  ,NumberOfElements(iProc*3+2), &
                                      ' |'  ,NumberOfElements(iProc*3+3), ' |'
  END DO
END IF
CALL MPI_BARRIER(MPI_COMM_FLEXI,iError)
#endif /*CODE_ANALYZE*/

! Loop over all elements and build a global FIBGM to processor mapping. This is required to identify potential emission procs
firstElem = INT(REAL( myComputeNodeRank   *nGlobalElems)/REAL(nComputeNodeProcessors))+1
lastElem  = INT(REAL((myComputeNodeRank+1)*nGlobalElems)/REAL(nComputeNodeProcessors))

BGMiglobDelta = BGMimaxglob - BGMiminglob
BGMjglobDelta = BGMjmaxglob - BGMjminglob
BGMkglobDelta = BGMkmaxglob - BGMkminglob

! Allocate array to hold the number of elemebts on each FIBGM cell
CALL Allocate_Shared((/(BGMiglobDelta+1)*(BGMjglobDelta+1)*(BGMkglobDelta+1)/)                    &
                    ,FIBGM_nTotalElems_Shared_Win,FIBGM_nTotalElems_Shared)
CALL MPI_WIN_LOCK_ALL(0,FIBGM_nTotalElems_Shared_Win,IERROR)

! Allocate flags which procs belong to which FIGBM cell
CALL Allocate_Shared((/(BGMiglobDelta+1)*(BGMjglobDelta+1)*(BGMkglobDelta+1)*nProcessors_Global/) &
                    ,FIBGMToProcFlag_Shared_Win,FIBGMToProcFlag_Shared)
CALL MPI_WIN_LOCK_ALL(0,FIBGMToProcFlag_Shared_Win,IERROR)
FIBGM_nTotalElems(BGMiminglob:BGMimaxglob,BGMjminglob:BGMjmaxglob,BGMkminglob:BGMkmaxglob)                        => FIBGM_nTotalElems_Shared
FIBGMToProcFlag  (BGMiminglob:BGMimaxglob,BGMjminglob:BGMjmaxglob,BGMkminglob:BGMkmaxglob,0:nProcessors_Global-1) => FIBGMToProcFlag_Shared

IF (myComputeNodeRank.EQ.0) THEN
  FIBGMToProcFlag   = .FALSE.
  FIBGM_nTotalElems = 0
END IF

CALL BARRIER_AND_SYNC(FIBGM_nTotalElems_Shared_Win,MPI_COMM_SHARED)
CALL BARRIER_AND_SYNC(FIBGMToProcFlag_Shared_Win  ,MPI_COMM_SHARED)

! Count number of global elements
DO iElem = firstElem,lastElem
  ProcRank = ElemInfo_Shared(ELEM_RANK,iElem)

  DO kBGM = ElemToBGM_Shared(5,iElem),ElemToBGM_Shared(6,iElem)
    DO jBGM = ElemToBGM_Shared(3,iElem),ElemToBGM_Shared(4,iElem)
      DO iBGM = ElemToBGM_Shared(1,iElem),ElemToBGM_Shared(2,iElem)
        ASSOCIATE(posElem =>     (kBGM-1)*(BGMiglobDelta+1)*(BGMjglobDelta+1)                   + (jBGM-1)*(BGMiglobDelta+1)                   + (iBGM-1), &
                  posRank => INT(ProcRank*(BGMiglobDelta+1)*(BGMjglobDelta+1)*(BGMkglobDelta+1) + (kBGM-1)*(BGMiglobDelta+1)*(BGMjglobDelta+1) + (jBGM-1)*(BGMiglobDelta+1) + (iBGM-1),KIND=MPI_ADDRESS_KIND))

          ! Increment number of elements on FIBGM cell
          CALL MPI_FETCH_AND_OP(increment,dummyInt,MPI_INTEGER,0,INT(posElem*SIZE_INT,MPI_ADDRESS_KIND),MPI_SUM,FIBGM_nTotalElems_Shared_Win,IERROR)
          ! Perform logical OR and place data on CN root
          CALL MPI_FETCH_AND_OP(.TRUE.   ,dummyLog,MPI_LOGICAL,0,INT(posRank*SIZE_INT,MPI_ADDRESS_KIND),MPI_LOR,FIBGMToProcFlag_Shared_Win  ,IERROR)
        END ASSOCIATE
      END DO
    END DO
  END DO
END DO

CALL BARRIER_AND_SYNC(FIBGMToProcFlag_Shared_Win  ,MPI_COMM_SHARED)
CALL BARRIER_AND_SYNC(FIBGM_nTotalElems_Shared_Win,MPI_COMM_SHARED)

! Allocate shared array to hold the mapping
CALL Allocate_Shared((/2,BGMimaxglob-BGMiminglob+1,BGMjmaxglob-BGMjminglob+1,BGMkmaxglob-BGMkminglob+1/), &
                       FIBGMToProc_Shared_Win,FIBGMToProc_Shared)
CALL MPI_WIN_LOCK_ALL(0,FIBGMToProc_Shared_Win,IERROR)
FIBGMToProc => FIBGMToProc_Shared

IF (myComputeNodeRank.EQ.0) THEN
  FIBGMToProc = 0
END IF
CALL BARRIER_AND_SYNC(FIBGMToProc_Shared_Win,MPI_COMM_SHARED)

! CN root build the mapping to avoid further communication
IF (myComputeNodeRank.EQ.0) THEN
  nFIBGMToProc = 0

  DO kBGM = BGMkminglob,BGMkmaxglob
    DO jBGM = BGMjminglob,BGMjmaxglob
      DO iBGM = BGMiminglob,BGMimaxglob
        ! Save current offset
        FIBGMToProc(FIBGM_FIRSTPROCIND,iBGM,jBGM,kBGM) = nFIBGMToProc
        ! Save number of procs per FIBGM element
        DO iProc = 0,nProcessors_Global-1
          ! Proc belongs to current FIBGM cell
          IF (FIBGMToProcFlag(iBGM,jBGM,kBGM,iProc)) THEN
            nFIBGMToProc = nFIBGMToProc + 1
            FIBGMToProc(FIBGM_NPROCS,iBGM,jBGM,kBGM) = FIBGMToProc(FIBGM_NPROCS,iBGM,jBGM,kBGM) + 1
          END IF
        END DO
      END DO
    END DO
  END DO
END IF

! Synchronize array and communicate the information to other procs on CN node
CALL BARRIER_AND_SYNC(FIBGMToProc_Shared_Win,MPI_COMM_SHARED)
CALL MPI_BCAST(nFIBGMToProc,1,MPI_INTEGER,0,MPI_COMM_SHARED,iError)

! Allocate shared array to hold the proc information
CALL Allocate_Shared((/nFIBGMToProc/),FIBGMProcs_Shared_Win,FIBGMProcs_Shared)
CALL MPI_WIN_LOCK_ALL(0,FIBGMProcs_Shared_Win,IERROR)
FIBGMProcs => FIBGMProcs_Shared

IF (myComputeNodeRank.EQ.0) THEN
  FIBGMProcs= -1
END IF
CALL BARRIER_AND_SYNC(FIBGMProcs_Shared_Win,MPI_COMM_SHARED)

! CN root fills the information
IF (myComputeNodeRank.EQ.0) THEN
  nFIBGMToProc = 0

  DO kBGM = BGMkminglob,BGMkmaxglob
    DO jBGM = BGMjminglob,BGMjmaxglob
      DO iBGM = BGMiminglob,BGMimaxglob
        ! Save proc ID
        DO iProc = 0,nProcessors_Global-1
          ! Proc belongs to current FIBGM cell
          IF (FIBGMToProcFlag(iBGM,jBGM,kBGM,iProc)) THEN
            nFIBGMToProc = nFIBGMToProc + 1
            FIBGMProcs(nFIBGMToProc) = iProc
          END IF
        END DO
      END DO
    END DO
  END DO
END IF

! De-allocate FLAG array
CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)
CALL MPI_WIN_UNLOCK_ALL(FIBGMToProcFlag_Shared_Win,iError)
CALL MPI_WIN_FREE(FIBGMToProcFlag_Shared_Win,iError)
CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)

! Then, free the pointers or arrays
MDEALLOCATE(FIBGMToProcFlag_Shared)
MDEALLOCATE(FIBGMToProcFlag)

CALL BARRIER_AND_SYNC(FIBGMProcs_Shared_Win,MPI_COMM_SHARED)
#endif /*USE_MPI*/

! and get max number of bgm-elems
ALLOCATE(Distance    (1:MAXVAL(FIBGM_nElems)) &
        ,ListDistance(1:MAXVAL(FIBGM_nElems)) )

#if USE_MPI
! Build a local nNonUniqueSides to nComputeNodeSides/nComputeNodeTotalSides mapping
ALLOCATE(CNTotalSide2GlobalSide(1:nComputeNodeTotalSides))
ALLOCATE(GlobalSide2CNTotalSide(1:nNonUniqueGlobalSides))

! Use MessageSize to temporally store the previous value
MessageSize = nComputeNodeTotalSides
nComputeNodeSides      = 0
nComputeNodeTotalSides = 0
GlobalSide2CNTotalSide(:) = -1
CNTotalSide2GlobalSide(:) = -1

! CN-local elements
DO iElem = 1,nComputeNodeElems
  ElemID = iElem + offsetComputeNodeElem

  ! Loop over all sides
  DO iSide = ElemInfo_Shared(ELEM_FIRSTSIDEIND,ElemID)+1,ElemInfo_Shared(ELEM_LASTSIDEIND,ElemID)
    ! Check if side was already added
    ! IF (GlobalSide2CNTotalSide(iSide).NE.-1) CYCLE

    nComputeNodeSides             = nComputeNodeSides      + 1
    nComputeNodeTotalSides        = nComputeNodeTotalSides + 1
    CNTotalSide2GlobalSide(nComputeNodeTotalSides) = iSide
    GlobalSide2CNTotalSide(iSide) = nComputeNodeTotalSides
  END DO
END DO

! CN-halo elements
Do iElem = nComputeNodeElems + 1,nComputeNodeTotalElems
  ElemID = CNTotalElem2GlobalElem(iElem)

  ! Loop over all sides
  DO iSide = ElemInfo_Shared(ELEM_FIRSTSIDEIND,ElemID)+1,ElemInfo_Shared(ELEM_LASTSIDEIND,ElemID)
    ! Check if side was already added
    ! IF (GlobalSide2CNTotalSide(iSide).NE.-1) CYCLE

    nComputeNodeTotalSides        = nComputeNodeTotalSides + 1
    CNTotalSide2GlobalSide(nComputeNodeTotalSides) = iSide
    GlobalSide2CNTotalSide(iSide) = nComputeNodeTotalSides
  END DO
END DO

! Sanity check
IF (nComputeNodeSides.NE.ElemInfo_Shared(ELEM_LASTSIDEIND,offsetComputeNodeElem+nComputeNodeElems)-ElemInfo_Shared(ELEM_FIRSTSIDEIND,offsetComputeNodeElem+1)) &
  CALL ABORT(__STAMP__,'Error with number of local sides on compute node')

IF (nComputeNodeTotalSides.NE.MessageSize) &
  CALL ABORT(__STAMP__,'Error with number of halo sides on compute node')

! ElemToBGM is only used during init. First, free every shared memory window. This requires MPI_BARRIER as per MPI3.1 specification
CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)

CALL MPI_WIN_UNLOCK_ALL(ElemToBGM_Shared_Win,iError)
CALL MPI_WIN_FREE(ElemToBGM_Shared_Win,iError)

CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)

#endif /*USE_MPI*/
! Then, free the pointers or arrays
MDEALLOCATE(ElemToBGM_Shared)

END SUBROUTINE BuildBGMAndIdentifyHaloRegion


SUBROUTINE FinalizeBGM()
!===================================================================================================================================
! Deallocates variables for the particle background mesh
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Mesh_Vars
USE MOD_Particle_MPI_Shared_Vars
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

! First, free every shared memory window. This requires MPI_BARRIER as per MPI3.1 specification
#if USE_MPI
CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)

CALL MPI_WIN_UNLOCK_ALL(BoundsOfElem_Shared_Win,iError)
CALL MPI_WIN_FREE(BoundsOfElem_Shared_Win,iError)
CALL MPI_WIN_UNLOCK_ALL(FIBGM_nTotalElems_Shared_Win,iError)
CALL MPI_WIN_FREE(FIBGM_nTotalElems_Shared_Win,iError)
CALL MPI_WIN_UNLOCK_ALL(FIBGM_nElems_Shared_Win,iError)
CALL MPI_WIN_FREE(FIBGM_nElems_Shared_Win,iError)
CALL MPI_WIN_UNLOCK_ALL(FIBGM_offsetElem_Shared_Win,iError)
CALL MPI_WIN_FREE(FIBGM_offsetElem_Shared_Win,iError)
CALL MPI_WIN_UNLOCK_ALL(FIBGM_Element_Shared_Win,iError)
CALL MPI_WIN_FREE(FIBGM_Element_Shared_Win,iError)
CALL MPI_WIN_UNLOCK_ALL(FIBGMToProc_Shared_Win,iError)
CALL MPI_WIN_FREE(FIBGMToProc_Shared_Win,iError)
CALL MPI_WIN_UNLOCK_ALL(FIBGMProcs_Shared_Win,iError)
CALL MPI_WIN_FREE(FIBGMProcs_Shared_Win,iError)

CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)

! Then, free the pointers or arrays
SDEALLOCATE(CNTotalElem2GlobalElem)
SDEALLOCATE(GlobalElem2CNTotalElem)
SDEALLOCATE(CNTotalSide2GlobalSide)
SDEALLOCATE(GlobalSide2CNTotalSide)
#endif /*USE_MPI*/

MDEALLOCATE(FIBGM_nElems)
MDEALLOCATE(FIBGM_offsetElem)
MDEALLOCATE(FIBGM_Element)
MDEALLOCATE(BoundsOfElem_Shared)
MDEALLOCATE(FIBGM_nTotalElems_Shared)
MDEALLOCATE(FIBGM_nElems_Shared)
MDEALLOCATE(FIBGM_offsetElem_Shared)
MDEALLOCATE(FIBGM_Element_Shared)
MDEALLOCATE(FIBGMToProc)
MDEALLOCATE(FIBGMToProc_Shared)
MDEALLOCATE(FIBGMProcs)
MDEALLOCATE(FIBGMProcs_Shared)

#if USE_MPI
CALL FinalizeHaloInfo()
#endif /*USE_MPI*/

END SUBROUTINE FinalizeBGM


#if USE_MPI
!===================================================================================================================================
! Writes the HaloFlag of each compute-node into an ElemData array 'CNRankX_ElemHaloInfo'
!===================================================================================================================================
SUBROUTINE WriteHaloInfo()
! MODULES                                                                                                                          !
USE MOD_Globals
USE MOD_Preproc
USE MOD_IO_HDF5                 ,ONLY: AddToElemData,ElementOut
USE MOD_Mesh_Vars               ,ONLY: nGlobalElems,offsetElem
USE MOD_Particle_Globals        ,ONLY: PP_nElems
USE MOD_Particle_MPI_Shared     ,ONLY: Allocate_Shared,MPI_SIZE,BARRIER_AND_SYNC
USE MOD_Particle_MPI_Shared_Vars,ONLY: myComputeNodeRank,myLeaderGroupRank,nLeaderGroupProcs
USE MOD_Particle_MPI_Shared_Vars,ONLY: MPI_COMM_SHARED,MPI_COMM_LEADERS_SHARED
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemHaloID
USE MOD_Particle_Mesh_Vars      ,ONLY: ElemHaloInfo_Array,ElemHaloInfo_Shared,ElemHaloInfo_Shared_Win,ElemInfo_Shared
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES

!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iRank,iElem
CHARACTER(LEN=255)             :: tmpStr
!===================================================================================================================================

SWRITE(UNIT_stdOut,'(A)',ADVANCE='YES') " ADDING halo debug information to State file..."

! Allocate array in shared memory for each compute-node rank
CALL Allocate_Shared((/nGlobalElems*nLeaderGroupProcs/),ElemHaloInfo_Shared_Win,ElemHaloInfo_Array)
CALL MPI_WIN_LOCK_ALL(0,ElemHaloInfo_Shared_Win,iERROR)
ElemHaloInfo_Shared(1:nGlobalElems,0:nLeaderGroupProcs-1) => ElemHaloInfo_Array

ElemHaloInfo_Shared(:,myLeaderGroupRank) = ElemInfo_Shared(ELEM_HALOFLAG,:)

! Communicate halo information between compute-nodes
IF (myComputeNodeRank.EQ.0) THEN
  DO iRank = 0,nLeaderGroupProcs-1
    CALL MPI_BCAST(ElemHaloInfo_Shared(:,iRank),nGlobalElems,MPI_INTEGER,iRank,MPI_COMM_LEADERS_SHARED,iERROR)
  END DO
END IF

! Synchronize information on each compute-node
CALL BARRIER_AND_SYNC(ElemHaloInfo_Shared_Win,MPI_COMM_SHARED)

! Add ElemInfo halo information to ElemData
DO iRank = 0,nLeaderGroupProcs-1
  WRITE(UNIT=tmpStr,FMT='(I0)') iRank
  CALL AddToElemData(ElementOut,'CNRank'//TRIM(tmpStr)//'_ElemHaloInfo',IntArray=ElemHaloInfo_Shared(offsetElem+1:offsetElem+PP_nElems,iRank))
END DO

! Add ElemHaloID information to ElemData to ease debugging
ALLOCATE(ElemHaloID(1:PP_nElems))
DO iElem = 1,PP_nElems
  ElemHaloID(iElem) = offsetElem+iElem
END DO
CALL AddToElemData(ElementOut,'ElemID',IntArray=ElemHaloID)

END SUBROUTINE WriteHaloInfo


!===================================================================================================================================
! Deallocates variables for the particle halo debug information
!===================================================================================================================================
SUBROUTINE FinalizeHaloInfo()
! MODULES                                                                                                                          !
USE MOD_Globals
USE MOD_Preproc
USE MOD_Particle_Mesh_Vars      ,ONLY: CalcHaloInfo,ElemHaloInfo_Array,ElemHaloInfo_Shared,ElemHaloInfo_Shared_Win
USE MOD_Particle_MPI_Shared_Vars,ONLY: MPI_COMM_SHARED
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES

!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

IF (.NOT.CalcHaloInfo) RETURN

! First, free every shared memory window. This requires MPI_BARRIER as per MPI3.1 specification
CALL MPI_BARRIER(MPI_COMM_SHARED,iERROR)
CALL MPI_WIN_UNLOCK_ALL(ElemHaloInfo_Shared_Win,iError)
CALL MPI_WIN_FREE(      ElemHaloInfo_Shared_Win,iError)

! Then, free the pointers or arrays
MDEALLOCATE(ElemHaloInfo_Shared)
MDEALLOCATE(ElemHaloInfo_Array)

END SUBROUTINE FinalizeHaloInfo
#endif /*USE_MPI*/


#if USE_MPI
SUBROUTINE CheckPeriodicSides()
!===================================================================================================================================
!> checks the elements against periodic distance
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Preproc
USE MOD_Mesh_Vars              ,ONLY: nGlobalElems
USE MOD_MPI_Vars               ,ONLY: offsetElemMPI
USE MOD_Particle_Globals       ,ONLY: VECNORM
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemInfo_Shared,BoundsOfElem_Shared,nComputeNodeElems
USE MOD_Particle_MPI_Shared_Vars
USE MOD_Particle_MPI_Vars      ,ONLY: halo_eps
USE MOD_Particle_Tracking_Vars ,ONLY: TrackingMethod
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iElem,firstElem,lastElem,iDir,jDir,kDir
INTEGER                        :: iLocElem
INTEGER                        :: iPeriodicVector,jPeriodicVector
REAL                           :: BoundsOfElemCenter(1:4),LocalBoundsOfElemCenter(1:4)
!===================================================================================================================================

firstElem = INT(REAL( myComputeNodeRank   *nGlobalElems)/REAL(nComputeNodeProcessors))+1
lastElem  = INT(REAL((myComputeNodeRank+1)*nGlobalElems)/REAL(nComputeNodeProcessors))

! The code below changes ElemInfo_Shared, identification of periodic elements must complete before
CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)

! This is a distributed loop. Nonetheless, the load will be unbalanced due to the location of the space-filling curve. Still,
! this approach is again preferred compared to the communication overhead.
DO iElem = firstElem,lastElem
  ! only consider elements that are not already flagged
  IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).GT.0) CYCLE

  BoundsOfElemCenter(1:3) = (/    SUM(BoundsOfElem_Shared(1:2,1,iElem)),                                                      &
                                  SUM(BoundsOfElem_Shared(1:2,2,iElem)),                                                      &
                                  SUM(BoundsOfElem_Shared(1:2,3,iElem)) /) / 2.
  BoundsOfElemCenter(4) = VECNORM ((/ BoundsOfElem_Shared(2,1,iElem)-BoundsOfElem_Shared(1,1,iElem),                       &
                                      BoundsOfElem_Shared(2,2,iElem)-BoundsOfElem_Shared(1,2,iElem),                       &
                                      BoundsOfElem_Shared(2,3,iElem)-BoundsOfElem_Shared(1,3,iElem) /) / 2.)

! Use a named loop so the entire element can be cycled
ElemLoop: DO iLocElem = offsetElemMPI(ComputeNodeRootRank)+1, offsetElemMPI(ComputeNodeRootRank)+nComputeNodeElems
    ! element might be already added back
    IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).GT.0) EXIT ElemLoop

    LocalBoundsOfElemCenter(1:3) = (/ SUM(   BoundsOfElem_Shared(1:2,1,iLocElem)),                                         &
                                      SUM(   BoundsOfElem_Shared(1:2,2,iLocElem)),                                         &
                                      SUM(   BoundsOfElem_Shared(1:2,3,iLocElem)) /) / 2.
    LocalBoundsOfElemCenter(4) = VECNORM ((/ BoundsOfElem_Shared(2  ,1,iLocElem)-BoundsOfElem_Shared(1,1,iLocElem),        &
                                             BoundsOfElem_Shared(2  ,2,iLocElem)-BoundsOfElem_Shared(1,2,iLocElem),        &
                                             BoundsOfElem_Shared(2  ,3,iLocElem)-BoundsOfElem_Shared(1,3,iLocElem) /) / 2.)

    SELECT CASE(GEO%nPeriodicVectors)

      CASE(1)
        ! check two directions
        DO iDir = -1, 1, 2
          ! check if element is within halo_eps of periodically displaced element
          IF (VECNORM( BoundsOfElemCenter(1:3) + GEO%PeriodicVectors(1:3,1)*REAL(iDir) - LocalBoundsOfElemCenter(1:3))&
                  .LE. halo_eps+BoundsOfElemCenter(4)+LocalBoundsOfElemCenter(4))THEN
            ! add element back to halo region
            ElemInfo_Shared(ELEM_HALOFLAG,iElem) = 3
            IF (TrackingMethod.EQ.REFMAPPING) CALL AddElementToFIBGM(iElem)
            EXIT ElemLoop
          END IF
        END DO

      CASE(2)
        ! check the two possible periodic vectors. Begin with checking the single periodic vector, followed by the combination of
        ! the first periodic vector with the other, 1,2,1+2
        DO iPeriodicVector = 1,2
          ! element might be already added back
          IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).GT.0) EXIT ElemLoop

          DO iDir = -1, 1, 2
            ! check if element is within halo_eps of periodically displaced element
            IF (VECNORM( BoundsOfElemCenter(1:3)                                                           &
                      + GEO%PeriodicVectors(1:3,iPeriodicVector)*REAL(iDir) - LocalBoundsOfElemCenter(1:3))&
                      .LE. halo_eps+BoundsOfElemCenter(4)+LocalBoundsOfElemCenter(4))THEN
              ! add element back to halo region
              ElemInfo_Shared(ELEM_HALOFLAG,iElem) = 3
              IF (TrackingMethod.EQ.REFMAPPING) CALL AddElementToFIBGM(iElem)
              EXIT ElemLoop
            END IF
          END DO ! iDir = -1, 1, 2

          ! Check linear combination of two periodic vectors
          DO jPeriodicVector = 1,2
            IF (iPeriodicVector.GE.jPeriodicVector) CYCLE

            DO iDir = -1, 1, 2
              DO jDir = -1, 1, 2
                ! check if element is within halo_eps of periodically displaced element
                IF (VECNORM( BoundsOfElemCenter(1:3)                                                             &
                          + GEO%PeriodicVectors(1:3,iPeriodicVector)*REAL(iDir)                                  &
                          + GEO%PeriodicVectors(1:3,jPeriodicVector)*REAL(jDir) - LocalBoundsOfElemCenter(1:3) ) &
                          .LE. halo_eps+BoundsOfElemCenter(4)+LocalBoundsOfElemCenter(4))THEN
                  ! add element back to halo region
                  ElemInfo_Shared(ELEM_HALOFLAG,iElem) = 3
                  IF (TrackingMethod.EQ.REFMAPPING) CALL AddElementToFIBGM(iElem)
                  EXIT ElemLoop
                END IF
              END DO ! jDir = -1, 1, 2
            END DO ! iDir = -1, 1, 2

          END DO ! jPeriodicVector = 1,2
        END DO ! iPeriodicVector = 1,2

      CASE(3)
        ! check the three periodic vectors. Begin with checking the first periodic vector, followed by the combination of
        ! the first periodic vector with the others. Then check the other combinations, i.e. 1, 1+2, 1+3, 2, 2+3, 3, 1+2+3
        DO iPeriodicVector = 1,3
          ! element might be already added back
          IF (ElemInfo_Shared(ELEM_HALOFLAG,iElem).GT.0) EXIT ElemLoop

          ! check if element is within halo_eps of periodically displaced element
          DO iDir = -1, 1, 2
            ! check if element is within halo_eps of periodically displaced element
            IF (VECNORM( BoundsOfElemCenter(1:3)                                                           &
                      + GEO%PeriodicVectors(1:3,iPeriodicVector)*REAL(iDir) - LocalBoundsOfElemCenter(1:3))&
                      .LE. halo_eps+BoundsOfElemCenter(4)+LocalBoundsOfElemCenter(4))THEN
              ! add element back to halo region
              ElemInfo_Shared(ELEM_HALOFLAG,iElem) = 3
              IF (TrackingMethod.EQ.REFMAPPING) CALL AddElementToFIBGM(iElem)
              EXIT ElemLoop
            END IF
          END DO ! iDir = -1, 1, 2

          ! Combination of two periodic vectors
          DO jPeriodicVector = 1,3
            IF (iPeriodicVector.GE.jPeriodicVector) CYCLE

            DO iDir = -1, 1, 2
              DO jDir = -1, 1, 2
                ! check if element is within halo_eps of periodically displaced element
                IF (VECNORM( BoundsOfElemCenter(1:3)                                                             &
                          + GEO%PeriodicVectors(1:3,iPeriodicVector)*REAL(iDir)                                  &
                          + GEO%PeriodicVectors(1:3,jPeriodicVector)*REAL(jDir) - LocalBoundsOfElemCenter(1:3) ) &
                          .LE. halo_eps+BoundsOfElemCenter(4)+LocalBoundsOfElemCenter(4))THEN
                  ! add element back to halo region
                  ElemInfo_Shared(ELEM_HALOFLAG,iElem) = 3
                  IF (TrackingMethod.EQ.REFMAPPING) CALL AddElementToFIBGM(iElem)
                  EXIT ElemLoop
                END IF
              END DO ! jDir = -1, 1, 2
            END DO ! iDir = -1, 1, 2

          END DO ! jPeriodicVector = 1,3
        END DO ! iPeriodicVector = 1,3

        ! Combination of three periodic vectors
        DO iDir = -1, 1, 2
          DO jDir = -1, 1, 2
            DO kDir = -1, 1, 2
            ! check if element is within halo_eps of periodically displaced element
              IF (VECNORM( BoundsOfElemCenter(1:3)                                                             &
                        + GEO%PeriodicVectors(1:3,1)*REAL(iDir)                                  &
                        + GEO%PeriodicVectors(1:3,2)*REAL(jDir)                                  &
                        + GEO%PeriodicVectors(1:3,3)*REAL(kDir) - LocalBoundsOfElemCenter(1:3) ) &
                        .LE. halo_eps+BoundsOfElemCenter(4)+LocalBoundsOfElemCenter(4))THEN
                ! add element back to halo region
                ElemInfo_Shared(ELEM_HALOFLAG,iElem) = 3
                IF (TrackingMethod.EQ.REFMAPPING) CALL AddElementToFIBGM(iElem)
                EXIT ElemLoop
              END IF
            END DO ! kDir = -1, 1, 2
          END DO ! jDir = -1, 1, 2
        END DO ! iDir = -1, 1, 2

      END SELECT
  END DO ElemLoop
END DO

END SUBROUTINE CheckPeriodicSides


SUBROUTINE AddElementToFIBGM(ElemID)
!===================================================================================================================================
!> adds an element to all corresponding FIBGM cells and ensures correct bounds
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemToBGM_Shared
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
INTEGER,INTENT(IN)             :: ElemID
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iBGM,jBGM,kBGM
INTEGER                        :: BGMCellXmax,BGMCellXmin,BGMCellYmax,BGMCellYmin,BGMCellZmax,BGMCellZmin
!===================================================================================================================================

BGMCellXmin = MAX(ElemToBGM_Shared(1,ElemID),GEO%FIBGMimin)
BGMCellXmax = MIN(ElemToBGM_Shared(2,ElemID),GEO%FIBGMimax)
BGMCellYmin = MAX(ElemToBGM_Shared(3,ElemID),GEO%FIBGMjmin)
BGMCellYmax = MIN(ElemToBGM_Shared(4,ElemID),GEO%FIBGMjmax)
BGMCellZmin = MAX(ElemToBGM_Shared(5,ElemID),GEO%FIBGMkmin)
BGMCellZmax = MIN(ElemToBGM_Shared(6,ElemID),GEO%FIBGMkmax)

! add current element to number of BGM-elems
DO iBGM = BGMCellXmin,BGMCellXmax
  DO jBGM = BGMCellYmin,BGMCellYmax
    DO kBGM = BGMCellZmin,BGMCellZmax
      GEO%FIBGM(iBGM,jBGM,kBGM)%nElem = GEO%FIBGM(iBGM,jBGM,kBGM)%nElem + 1
    END DO ! kBGM
  END DO ! jBGM
END DO ! iBGM

END SUBROUTINE


#if GCC_VERSION < 90000
PURE FUNCTION FINDLOC(Array,Value,Dim)
!===================================================================================================================================
!> Implements a subset of the intrinsic FINDLOC function for Fortran < 2008
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
INTEGER,INTENT(IN)             :: Array(:)
INTEGER,INTENT(IN)             :: Value
INTEGER,INTENT(IN)             :: Dim
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
INTEGER                        :: FINDLOC
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iVar
!===================================================================================================================================
DO iVar = 1,SIZE(ARRAY,1)
  IF (Array(iVar).EQ.Value) THEN
    FINDLOC = iVar
    RETURN
  END IF
END DO

! Return error code -1 if the value was not found
FINDLOC = -1

END FUNCTION FINDLOC
#endif /*GCC_VERSION < 90000*/
#endif /*USE_MPI*/


END MODULE MOD_Particle_BGM
