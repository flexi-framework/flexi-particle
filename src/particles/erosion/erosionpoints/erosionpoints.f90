!=================================================================================================================================
! Copyright (c) 2010-2016  Prof. Claus-Dieter Munz 
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://nrg.iag.uni-stuttgart.de/
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License 
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PUEPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
#include "flexi.h"

!==================================================================================================================================
!> Module that provides functions for computing the solutions time history at a defined set of points ("erosionpoints")
!==================================================================================================================================
MODULE MOD_ErosionPoints
! MODULES
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
INTERFACE DefineParametersErosionPoints
  MODULE PROCEDURE DefineParametersErosionPoints
END INTERFACE

INTERFACE InitErosionPoints
  MODULE PROCEDURE InitErosionPoints
END INTERFACE

INTERFACE WriteEP
  MODULE PROCEDURE WriteEP
END INTERFACE

INTERFACE RecordErosionPoint
  MODULE PROCEDURE RecordErosionPoint
END INTERFACE

INTERFACE RestartErosionPoint
  MODULE PROCEDURE RestartErosionPoint
END INTERFACE

INTERFACE FinalizeErosionPoints
  MODULE PROCEDURE FinalizeErosionPoints
END INTERFACE

PUBLIC::DefineParametersErosionPoints,InitErosionPoints,FinalizeErosionPoints
PUBLIC::RecordErosionPoint,RestartErosionPoint,WriteEP
!==================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Define parameters 
!==================================================================================================================================
SUBROUTINE DefineParametersErosionPoints()
! MODULES
USE MOD_ReadInTools ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection("ErosionPoints")
CALL prms%CreateLogicalOption('Part-EP_inUse',          "Set true to record individual particle impact data.",&
                                                   '.FALSE.')
CALL prms%CreateIntOption(    'Part-EP_MaxMemory',      "Maximum memory in MiB to be used for storing erosionpoint state history. ",&!//&
!                                                   "If memory is exceeded before regular IO level states are written to file.",&
                                                   '100')
END SUBROUTINE DefineParametersErosionPoints


!==================================================================================================================================
!> Init EP tracking
!==================================================================================================================================
SUBROUTINE InitErosionPoints()
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_ReadInTools         ,ONLY: GETSTR,GETINT,GETLOGICAL,GETREAL
USE MOD_Interpolation_Vars  ,ONLY: InterpolationInitIsDone
USE MOD_ErosionPoints_Vars
USE MOD_Particle_Boundary_Vars,     ONLY:SurfMesh
 IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: EP_maxMemory
INTEGER(KIND=8)       :: EP_maxBufferSize_glob
!==================================================================================================================================
! check if erosionpoints are activated
EP_inUse=GETLOGICAL('Part-EP_inUse','.FALSE.')
IF(.NOT.EP_inUse) RETURN

nEP_Procs = 0

IF((.NOT.InterpolationInitIsDone) .OR. ErosionPointsInitIsDone)THEN
   CALL Abort(__STAMP__,&
     "InitErosionPoints not ready to be called or already called.")
END IF
SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT EROSIONPOINTS...'

EP_maxMemory     = GETINT('Part-EP_MaxMemory','100')           ! Max buffer (100MB)
EP_MaxBufferSize = EP_MaxMemory*131072/EPDataSize    != size in bytes/(real*EPDataSize)

IF(SurfMesh%nSides.NE.0) THEN
  EP_onProc        = .TRUE.
  nEP_Procs        = 1
END IF

ALLOCATE(EP_Data(EP_MaxBufferSize,EPDataSize))

#if USE_MPI
CALL InitEPCommunicator()
CALL MPI_BARRIER(MPI_COMM_WORLD,iERROR)
CALL MPI_ALLREDUCE(MPI_IN_PLACE,nEP_Procs,1,MPI_INTEGER,MPI_SUM,MPI_COMM_WORLD,iError)
#endif /*USE_MPI*/

EP_Impacts = 0

! This might overflow a kind=4 integer, so use a larger on to be sure
EP_maxBufferSize_glob   = EP_MaxBufferSize*nEP_Procs

ErosionPointsInitIsDone=.TRUE.
SWRITE(UNIT_stdOut,'(A,I12,A,I12,A)') ' Buffer allocatated for max. ',EP_maxBufferSize_glob, ' impacts ( ',     &
                                                                      EP_MaxBufferSize,      ' impacts/proc)'
SWRITE(UNIT_stdOut,'(A)')' INIT EROSIONPOINTS DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')
END SUBROUTINE InitErosionPoints


#if USE_MPI
!==================================================================================================================================
!> Read EP parameters from ini file and EP definitions from HDF5
!==================================================================================================================================
SUBROUTINE InitEPCommunicator()
! MODULES
USE MOD_Globals
USE MOD_ErosionPoints_Vars   ,ONLY: EP_onProc,myEPrank,EP_COMM,nEP_Procs
 IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                   :: color,iProc
INTEGER                   :: noEPrank,EPrank
LOGICAL                   :: hasEP
!==================================================================================================================================
color=MPI_UNDEFINED
IF(EP_onProc) color=2

! create ranks for EP communicator
IF(MPIRoot) THEN
  EPrank=-1
  noEPrank=-1
  myEPRank=0
  IF(EP_onProc) THEN
    EPrank=0
  ELSE
    noEPrank=0
  END IF
  DO iProc=1,nProcessors-1
    CALL MPI_RECV(hasEP,1,MPI_LOGICAL,iProc,0,MPI_COMM_WORLD,MPIstatus,iError)
    IF(hasEP) THEN
      EPrank=EPrank+1
      CALL MPI_SEND(EPrank,1,MPI_INTEGER,iProc,0,MPI_COMM_WORLD,iError)
    ELSE
      noEPrank=noEPrank+1
      CALL MPI_SEND(noEPrank,1,MPI_INTEGER,iProc,0,MPI_COMM_WORLD,iError)
    END IF
  END DO
ELSE
    CALL MPI_SEND(EP_onProc,1,MPI_LOGICAL,0,0,MPI_COMM_WORLD,iError)
    CALL MPI_RECV(myEPrank,1,MPI_INTEGER,0,0,MPI_COMM_WORLD,MPIstatus,iError)
END IF

! create new EP communicator for EP output
CALL MPI_COMM_SPLIT(MPI_COMM_WORLD, color, myEPrank, EP_COMM,iError)
IF(EP_onProc) CALL MPI_COMM_SIZE(EP_COMM, nEP_Procs,iError)
IF(myEPrank.EQ.0 .AND. EP_onProc) WRITE(*,*) 'EP COMM:',nEP_Procs,'procs'

END SUBROUTINE InitEPCommunicator
#endif /*USE_MPI*/


SUBROUTINE RecordErosionPoint(BCSideID,PartID,PartFaceAngle,v_old,PartFaceAngle_old,PartReflCount)
!----------------------------------------------------------------------------------------------------------------------------------!
! Combined routine to add erosion impacts to tracking array
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Particle_Globals
USE MOD_TimeDisc_Vars,           ONLY: t
USE MOD_Particle_Boundary_Vars
USE MOD_Particle_Erosion_Vars
USE MOD_ErosionPoints_Vars
USE MOD_Particle_Vars,           ONLY: Species,PartState,PartSpecies,LastPartPos
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT VARIABLES 
REAL,INTENT(IN)                   :: PartFaceAngle, v_old(1:3)
REAL,INTENT(IN)                   :: PartFaceAngle_old
INTEGER,INTENT(IN)                :: BCSideID,PartID,PartReflCount
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                              :: v_magnitude_old,v_magnitude_new
REAL                              :: e_kin_old,e_kin_new
!===================================================================================================================================

!----  Calculating values before and after reflection
v_magnitude_old   = SQRT(DOT_PRODUCT(v_old(1:3),v_old(1:3)))
v_magnitude_new   = SQRT(DOT_PRODUCT(PartState(PartID,4:6),PartState(PartID,4:6)))
e_kin_old         = .5*Species(PartSpecies(PartID))%MassIC*v_magnitude_old**2.
e_kin_new         = .5*Species(PartSpecies(PartID))%MassIC*v_magnitude_new**2.
!e_kin_loss        = e_kin_old-e_kin_new

!IF ((e_kin_new.GT.e_kin_old).AND.(.NOT.ALMOSTEQUAL(e_kin_new,e_kin_old))) THEN
!    CALL abort(&
!      __STAMP__&
!      ,'Increase in kinetic energy upon reflection! Aborting ...')
!END IF

! LastParPos is set to impact location!

! Record individual impact
EP_Impacts = EP_Impacts + 1

EP_Data(EP_Impacts,1:3) = LastPartPos(PartID,1:3)
EP_Data(EP_Impacts,4:6) = v_old(1:3)
EP_Data(EP_Impacts,7)   = REAL(PartSpecies(PartID))
EP_Data(EP_Impacts,8)   = REAL(BCSideID)
EP_Data(EP_Impacts,9)   = t
EP_Data(EP_Impacts,10)  = REAL(PartReflCount)
EP_Data(EP_Impacts,11)  = e_kin_old
EP_Data(EP_Impacts,12)  = e_kin_new
EP_Data(EP_Impacts,13)  = PartFaceAngle_old
EP_Data(EP_Impacts,14)  = PartFaceAngle

END SUBROUTINE RecordErosionPoint


SUBROUTINE RestartErosionPoint
!==================================================================================================================================
!> Restarts the impact tracking. Needed before files are flushed
!==================================================================================================================================
USE MOD_Globals
USE MOD_IO_HDF5
USE MOD_HDF5_Input
USE MOD_HDF5_Output
USE MOD_Restart_Vars,               ONLY: RestartFile
USE MOD_Particle_Erosion_Vars
USE MOD_Erosionpoints_Vars
!----------------------------------------------------------------------------------------------------------------------------------!
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES

!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                        :: ErosionDataExists
INTEGER                        :: EP_glob
INTEGER                        :: ErosionDim              !dummy for rank of ErosionData
!==================================================================================================================================
!#if USE_MPI
! Ignore procs without erosion surfaces on them
!IF(SurfMesh%nSides.EQ.0) RETURN
!#endif
IF(MPIroot)THEN
    WRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='NO')' RESTARTING EROSIONPOINT DATA FROM HDF5 FILE...'
END IF

EP_Impacts = 0

! Open the restart file and search for erosionData
CALL OpenDataFile(RestartFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
CALL DatasetExists(File_ID,'ErosionData',ErosionDataExists)

IF(ErosionDataExists) THEN
    CALL GetDataSize(File_ID,'ErosionData',ErosionDim,HSize)
    CHECKSAFEINT(HSize(1),4)
    EP_glob    = INT(HSize(1))
    SWRITE(UNIT_stdOut,'(A3,A30,A3,I33)')' | ','Number of impacts',' | ',EP_glob
    ! We lost the impact <-> proc association, so fill the entire array
    CALL ReadArray(ArrayName='ErosionData', rank=2,&
                     nVal=      (/EP_glob  ,EPDataSize/),&
                     offset_in  = 0,&
                     offset_dim = 1,&
                     RealArray  = EP_Data(1:EP_glob,1:EPDataSize))
    ! Pretend all impacts happened on MPI_ROOT, so we can write out
    IF(MPIroot) THEN
        EP_Impacts = EP_glob
        WRITE(UNIT_stdOut,'(A)',ADVANCE='YES')' DONE'
        WRITE(UNIT_StdOut,'(132("-"))')
    END IF
END IF

END SUBROUTINE RestartErosionPoint


!==================================================================================================================================
!> Writes the time history of the solution at the erosionpoints to an HDF5 file
!==================================================================================================================================
SUBROUTINE WriteEP(OutputTime,resetCounters)
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE HDF5
USE MOD_IO_HDF5           ,ONLY: File_ID,OpenDataFile,CloseDataFile
USE MOD_HDF5_Output       ,ONLY: WriteAttribute,WriteArray,MarkWriteSuccessfull
USE MOD_Output_Vars       ,ONLY: ProjectName
#if USE_MPI
USE MOD_Erosionpoints_Vars ,ONLY: EP_COMM
USE MOD_Particle_HDF5_output,ONLY:DistributedWriteArray
#endif /*MPI*/
USE MOD_Particle_HDF5_output,ONLY:WriteAttributeToHDF5,WriteArrayToHDF5,WriteHDF5Header
USE MOD_ErosionPoints_Vars
!----------------------------------------------------------------------------------------------------------------------------------!
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
REAL,   INTENT(IN)             :: OutputTime            !< time
LOGICAL,INTENT(IN)             :: resetCounters         !< flag to reset sample counters and reallocate buffers, once file is done
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: locEP,EP_glob
CHARACTER(LEN=255)             :: FileName,FileString
CHARACTER(LEN=255),ALLOCATABLE :: StrVarNames(:)
REAL                           :: startT,endT
#if USE_MPI
INTEGER                        :: sendbuf(2),recvbuf(2)
INTEGER                        :: nImpacts(0:nProcessors-1)
#endif
!==================================================================================================================================
! Only use procs with surfaces on them
!IF(.NOT.EP_onProc) RETURN

! Find amount of recorded impacts on current proc
locEP   = EP_Impacts
EP_glob = 0

IF(MPIroot)THEN
!  WRITE(UNIT_StdOut,'(132("-"))')
  WRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='NO')' WRITE EROSIONPOINT DATA TO HDF5 FILE...'
!  WRITE(UNIT_stdOut,'(a,I4,a,I4,a)')' EP Buffer  : ',locEP,'/',EP_Buffersize,' impacts.'
  GETTIME(startT)
END IF

! Find our offset
#if USE_MPI
  sendbuf(1) = locEP
  recvbuf    = 0
  CALL MPI_EXSCAN(sendbuf(1),recvbuf(1),1,MPI_INTEGER,MPI_SUM,MPI_COMM_WORLD,iError)
  offsetEP   = recvbuf(1)
  sendbuf(1) = recvbuf(1)+locEP
  CALL MPI_BCAST(sendbuf(1),1,MPI_INTEGER,nProcessors-1,MPI_COMM_WORLD,iError)            !last proc knows global number
  !global numbers
  EP_glob    = sendbuf(1)
  CALL MPI_GATHER(locEP,1,MPI_INTEGER,nImpacts,1,MPI_INTEGER,0,MPI_COMM_WORLD,iError)
#else
  offsetEP   = 0
  EP_glob    = locEP
#endif
  
  EP_Buffersize = EP_glob
 
  ! Array for erosion point vars
  ALLOCATE(StrVarNames(EPDataSize))
  StrVarNames(1)='ParticlePositionX'
  StrVarNames(2)='ParticlePositionY'
  StrVarNames(3)='ParticlePositionZ'
  StrVarNames(4)='VelocityX'
  StrVarNames(5)='VelocityY'
  StrVarNames(6)='VelocityZ'
  StrVarNames(7)='Species'
  StrVarNames(8)='BoundaryNumber'
  StrVarNames(9) ='ImpactTime'
  StrVarNames(10)='ReflectionCount'
  StrVarNames(11)='E_kin_impact'
  StrVarNames(12)='E_kin_reflected'
  StrVarNames(13)='Alpha_impact'
  StrVarNames(14)='Alpha_reflected'
  
!IF(myEPrank.EQ.0)THEN
!  WRITE(UNIT_stdOut,'(a,I4,a,I4,a)')' EP Buffer  : ',locEP,' impacts local / ',EP_Buffersize,' impacts global.'
!END IF
  
  ! Get dedicated filled write array
!  ALLOCATE(EP_write(offsetEP+1:offsetEP+locEP,EPDataSize))
!  DO iEP=offsetEP+1,offsetEP+locEP
!  EP_write(offsetEP+1:offsetEP+locEP,EPDataSize) = EP_Data(1:locEP,EPDataSize)
!  END DO

  ! Regenerate state file skeleton
  FileName=TRIM(TIMESTAMP(TRIM(ProjectName)//'_State',OutputTime))
  FileString=TRIM(FileName)//'.h5'
  
  IF(MPIRoot)THEN
#if USE_MPI
    CALL OpenDataFile(FileString,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
#else
    CALL OpenDataFile(FileString,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
#endif
    CALL WriteAttributeToHDF5(File_ID,'VarNamesErosion',EPDataSize,StrArray=StrVarNames)
    CALL CloseDataFile()
  END IF

#if USE_MPI
 CALL DistributedWriteArray(FileString                             ,&
                            DataSetName='ErosionData',rank=2       ,&
                            nValGlobal=(/EP_glob    ,EPDataSize/)  ,&
                            nVal=      (/locEP      ,EPDataSize/)  ,&
                            offset=    (/offsetEP   ,0/)           ,&
                            collective=.FALSE.      ,offSetDim=1   ,&
                            communicator=MPI_COMM_WORLD,RealArray=EP_Data(1:locEP,1:EPDataSize))
#else
  CALL OpenDataFile(FileString,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)   
  CALL WriteArrayToHDF5(DataSetName='ErosionData'   ,rank=2         ,&
                        nValGlobal=(/EP_glob        ,EPDataSize/)   ,&
                        nVal=      (/locEP          ,EPDataSize  /) ,&
                        offset=    (/offsetEP       ,0  /)          ,&
                        collective=.TRUE., RealArray=EP_Data(1:locEP,1:EPDataSize))
  CALL CloseDataFile()
#endif /*MPI*/  
  
  ! Deallocate everything
  DEALLOCATE(StrVarNames)
  
  ! Erase record variables
  IF (resetCounters) THEN
    EP_Impacts = 0
    locEP      = 0
    EP_glob    = 0

    EP_Data    = 0.
  END IF

IF(MPIroot)THEN
!  CALL MarkWriteSuccessfull(FileName)
  GETTIME(EndT)
  WRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')' DONE  [',EndT-StartT,'s]'
  WRITE(UNIT_stdOut,'(a,I4,a,I4,a)')' EP Buffer  : ',locEP,' impacts local / ',EP_Buffersize,' impacts global.'
  WRITE(UNIT_StdOut,'(132("-"))')
END IF
END SUBROUTINE WriteEP


!==================================================================================================================================
!> Deallocate erosionpoint arrays
!==================================================================================================================================
SUBROUTINE FinalizeErosionPoints()
! MODULES
USE MOD_ErosionPoints_Vars
IMPLICIT NONE
!==================================================================================================================================
SDEALLOCATE(EP_Data)
ErosionPointsInitIsDone = .FALSE.

END SUBROUTINE FinalizeErosionPoints


END MODULE MOD_ErosionPoints