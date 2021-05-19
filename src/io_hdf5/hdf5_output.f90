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

!==================================================================================================================================
!> Module providing IO routines for parallel output in HDF5 format: solution, time averaged files, baseflow, record points,...
!==================================================================================================================================
MODULE MOD_HDF5_Output
! MODULES
USE MOD_IO_HDF5
USE MOD_HDF5_WriteArray
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------

INTERFACE WriteState
  MODULE PROCEDURE WriteState
END INTERFACE

INTERFACE WriteTimeAverage
  MODULE PROCEDURE WriteTimeAverage
END INTERFACE

INTERFACE WriteBaseflow
  MODULE PROCEDURE WriteBaseflow
END INTERFACE

INTERFACE FlushFiles
  MODULE PROCEDURE FlushFiles
END INTERFACE

INTERFACE WriteHeader
  MODULE PROCEDURE WriteHeader
END INTERFACE

INTERFACE WriteAttribute
  MODULE PROCEDURE WriteAttribute
END INTERFACE

INTERFACE MarkWriteSuccessfull
  MODULE PROCEDURE MarkWriteSuccessfull
END INTERFACE

INTERFACE WriteAdditionalElemData
  MODULE PROCEDURE WriteAdditionalElemData
END INTERFACE

INTERFACE
  SUBROUTINE copy_userblock(outfilename,infilename) BIND(C)
      USE ISO_C_BINDING, ONLY: C_CHAR
      CHARACTER(KIND=C_CHAR) :: outfilename(*)
      CHARACTER(KIND=C_CHAR) :: infilename(*)
  END SUBROUTINE copy_userblock
END INTERFACE

INTERFACE GenerateFileSkeleton
  MODULE PROCEDURE GenerateFileSkeleton
END INTERFACE


PUBLIC :: WriteState,FlushFiles,WriteHeader,WriteTimeAverage,WriteBaseflow,GenerateFileSkeleton
PUBLIC :: WriteAttribute,WriteAdditionalElemData,MarkWriteSuccessfull
!==================================================================================================================================

CONTAINS


!==================================================================================================================================
!> Subroutine to write the solution U to HDF5 format
!> Is used for postprocessing and for restart
!==================================================================================================================================
SUBROUTINE WriteState(MeshFileName,OutputTime,FutureTime,isErrorFile)
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_DG_Vars           ,ONLY: U
USE MOD_Output_Vars       ,ONLY: ProjectName,NOut,Vdm_N_NOut,WriteStateFiles
USE MOD_Mesh_Vars         ,ONLY: offsetElem,nGlobalElems,sJ,nElems
USE MOD_ChangeBasisByDim  ,ONLY: ChangeBasisVolume
USE MOD_Equation_Vars     ,ONLY: StrVarNames
#if PP_dim == 2
USE MOD_2D                ,ONLY: ExpandArrayTo3D
#endif
#if USE_RW
USE MOD_DG_Vars           ,ONLY: UTurb
USE MOD_Equation_Vars     ,ONLY: nVarTurb
USE MOD_Restart_Vars      ,ONLY: RestartTurb
#endif
#if USE_LOADBALANCE
USE MOD_Particle_HDF5_Output,ONLY: WriteElemTime
#endif /*USE_LOADBALANCE*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)    :: MeshFileName   !< file name of mesh used for simulation
REAL,INTENT(IN)                :: OutputTime     !< simulation time when output is performed
REAL,INTENT(IN)                :: FutureTime     !< hint, when next file will be written
LOGICAL,INTENT(IN)             :: isErrorFile    !< indicate whether an error file is written in case of a crashed simulation
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)             :: FileName,FileType
REAL                           :: StartT,EndT
REAL,POINTER                   :: UOut(:,:,:,:,:)
#if PP_dim == 2
REAL,ALLOCATABLE               :: UOutTmp(:,:,:,:,:)
#endif
REAL                           :: Utmp(5,0:PP_N,0:PP_N,0:PP_NZ)
REAL                           :: JN(1,0:PP_N,0:PP_N,0:PP_NZ),JOut(1,0:NOut,0:NOut,0:ZDIM(NOut))
INTEGER                        :: iElem,i,j,k
INTEGER                        :: nVal(5)
!==================================================================================================================================
IF (.NOT.WriteStateFiles) RETURN
IF(MPIRoot)THEN
  WRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' WRITE STATE TO HDF5 FILE...'
  GETTIME(StartT)
END IF

! Generate skeleton for the file with all relevant data on a single proc (MPIRoot)
FileType=MERGE('ERROR_State','State      ',isErrorFile)
FileName=TRIM(TIMESTAMP(TRIM(ProjectName)//'_'//TRIM(FileType),OutputTime))//'.h5'
#if USE_RW
IF (RestartTurb) THEN
  IF(MPIRoot) CALL GenerateFileSkeleton(TRIM(FileName),'State',PP_nVar+nVarTurb,NOut,StrVarNames,&
                                        MeshFileName,OutputTime,FutureTime,withUserblock=.TRUE.)
ELSE
#endif /* USE_RW */
  IF(MPIRoot) CALL GenerateFileSkeleton(TRIM(FileName),'State',PP_nVar,NOut,StrVarNames(1:PP_nVar),&
                                        MeshFileName,OutputTime,FutureTime,withUserblock=.TRUE.)
#if USE_RW
END IF
#endif /* USE_RW */

! Set size of output
nVal=(/PP_nVar,NOut+1,NOut+1,ZDIM(NOut)+1,nElems/)

! build output data
IF(NOut.NE.PP_N)THEN
#if FV_ENABLED
  CALL Abort(__STAMP__, &
      "NOut not working for FV!")
#endif
  ! Project JU and J to NOut, compute U on Nout
  ALLOCATE(UOut(PP_nVar,0:NOut,0:NOut,0:ZDIM(NOut),nElems))
  DO iElem=1,nElems
    JN(1,:,:,:)=1./sJ(:,:,:,iElem,0)
    DO k=0,PP_NZ; DO j=0,PP_N; DO i=0,PP_N
      Utmp(:,i,j,k)=U(:,i,j,k,iElem)*JN(1,i,j,k)
    END DO; END DO; END DO
    CALL ChangeBasisVolume(PP_nVar,PP_N,NOut,Vdm_N_NOut,&
                           Utmp,UOut(1:PP_nVar,:,:,:,iElem))
    ! Jacobian
    CALL ChangeBasisVolume(1,PP_N,NOut,Vdm_N_NOut,JN,JOut)
    DO k=0,ZDIM(NOut); DO j=0,NOut; DO i=0,NOut
      UOut(:,i,j,k,iElem)=UOut(:,i,j,k,iElem)/JOut(1,i,j,k)
    END DO; END DO; END DO
  END DO
#if PP_dim == 2
  ! If the output should be done with a full third dimension in a two dimensional computation, we need to expand the solution
  IF (.NOT.output2D) THEN
    ALLOCATE(UOutTmp(PP_nVar,0:NOut,0:NOut,0:ZDIM(NOut),nElems))
    UOutTmp = UOut
    DEALLOCATE(UOut)
    ALLOCATE(UOut(PP_nVar,0:NOut,0:NOut,0:NOut,nElems))
    CALL ExpandArrayTo3D(5,nVal,4,Nout+1,UOutTmp,UOut)
    DEALLOCATE(UOutTmp)
    nVal=(/PP_nVar,NOut+1,NOut+1,NOut+1,nElems/)
  END IF
#endif

ELSE ! write state on same polynomial degree as the solution

#if PP_dim == 3
#if USE_RW
  IF (RestartTurb) THEN
    ! Add UTurb to output for RW, we need to expand the solution
    ALLOCATE(UOut(1:PP_nVar+nVarTurb,0:NOut,0:NOut,0:ZDIM(NOut),nElems))
    Uout(1:PP_nVar,:,:,:,:)                  = U    (1:PP_nVar ,:,:,:,:)
    Uout(PP_nVar+1:PP_nVar+nVarTurb,:,:,:,:) = UTurb(1:nVarTurb,:,:,:,:)
    ! Correct size of the output array
    nVal=(/PP_nVar+nVarTurb,NOut+1,NOut+1,NOut+1,nElems/)
  ELSE
#endif /* USE_RW */
    UOut => U
#if USE_RW
  END IF
#endif /* USE_RW */
#else
  IF (.NOT.output2D) THEN
    ! If the output should be done with a full third dimension in a two dimensional computation, we need to expand the solution
    ALLOCATE(UOut(PP_nVar,0:NOut,0:NOut,0:NOut,nElems))
    CALL ExpandArrayTo3D(5,(/PP_nVar,NOut+1,NOut+1,ZDIM(NOut)+1,nElems/),4,NOut+1,U,UOut)
    ! Correct size of the output array
    nVal=(/PP_nVar,NOut+1,NOut+1,NOut+1,nElems/)
  ELSE
    UOut => U
  END IF
#endif
END IF ! (NOut.NE.PP_N)


! Reopen file and write DG solution
#if USE_MPI
CALL MPI_BARRIER(MPI_COMM_FLEXI,iError)
#endif
#if USE_RW
IF (RestartTurb) THEN
  CALL GatheredWriteArray(FileName,create=.FALSE.,&
                          DataSetName='DG_Solution', rank=5,&
                          nValGlobal=(/PP_nVar+nVarTurb,NOut+1,NOut+1,NOut+1,nGlobalElems/),&
                          nVal=nVal                                              ,&
                          offset=    (/0,      0,     0,     0,     offsetElem/),&
                          collective=.TRUE.,RealArray=UOut)
  ! UOut always separately allocated with RestartTurb
  DEALLOCATE(UOut)
ELSE
#endif
  CALL GatheredWriteArray(FileName,create=.FALSE.,&
                          DataSetName='DG_Solution', rank=5,&
                          nValGlobal=(/PP_nVar,NOut+1,NOut+1,NOut+1,nGlobalElems/),&
                          nVal=nVal                                              ,&
                          offset=    (/0,      0,     0,     0,     offsetElem/),&
                          collective=.TRUE.,RealArray=UOut)

  ! Deallocate UOut only if we did not point to U
  IF((PP_N .NE. NOut).OR.((PP_dim .EQ. 2).AND.(.NOT.output2D))) DEALLOCATE(UOut)
#if USE_RW
END IF
#endif

#if USE_PARTICLES
CALL WriteParticle(FileName)
#endif /*USE_PARTICLES*/
#if USE_LOADBALANCE
! Write 'ElemTime' to a separate container in the state.h5 file
CALL WriteElemTime(FileName)
#endif /*USE_LOADBALANCE*/

CALL WriteAdditionalElemData(FileName,ElementOut)
CALL WriteAdditionalFieldData(FileName,FieldOut)


IF(MPIRoot)THEN
  CALL MarkWriteSuccessfull(FileName)
  GETTIME(EndT)
  WRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')'DONE  [',EndT-StartT,'s]'
END IF

#if USE_MPI
! Since we are going to abort directly after this wenn an error state is written, make sure that all processors are finished
! with everything or we might end up with a non-valid error state file
IF (isErrorFile) CALL MPI_BARRIER(MPI_COMM_FLEXI,iError)
#endif
END SUBROUTINE WriteState


!==================================================================================================================================
!> Write additional data for analyze purpose to HDF5.
!> The data is taken from a lists, containing either pointers to data arrays or pointers
!> to functions to generate the data, along with the respective varnames.
!>
!> Two options are available:
!>    1. WriteAdditionalElemData:
!>       Element-wise scalar data, e.g. the timestep or indicators.
!>       The data is collected in a single array and written out in one step.
!>       DO NOT MISUSE NODAL DATA FOR THIS! IT WILL DRASTICALLY INCREASE FILE SIZE AND SLOW DOWN IO!
!>    2. WriteAdditionalFieldData:
!>       Nodal data, e.g. coordinates or sgs viscosities.
!>       Each list entry is written into a separate array.
!>
!> TODO:
!>    1. Writing items separatly is slow. Maybe use multiwrite features of coming HDF5.
!>    2. Reorder dimensions, so nVar is last for all arrays.
!==================================================================================================================================
SUBROUTINE WriteAdditionalElemData(FileName,ElemList)
! MODULES
USE MOD_Globals
USE MOD_Mesh_Vars,ONLY: offsetElem,nGlobalElems,nElems
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN)        :: FileName !< Name of the file to be written to
TYPE(tElementOut),POINTER,INTENT(IN) :: ElemList !< Linked list of arrays to write to file
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255),ALLOCATABLE :: VarNames(:)
REAL,ALLOCATABLE               :: ElemData(:,:)
INTEGER                        :: nVar
TYPE(tElementOut),POINTER      :: e
!==================================================================================================================================
IF(.NOT. ASSOCIATED(ElemList)) RETURN

! Count the additional variables
nVar = 0
e=>ElemList
DO WHILE(ASSOCIATED(e))
  nVar=nVar+1
  e=>e%next
END DO

! Allocate variable names and data array
ALLOCATE(VarNames(nVar))
ALLOCATE(ElemData(nVar,nElems))

! Fill the arrays
nVar = 0
e=>ElemList
DO WHILE(ASSOCIATED(e))
  nVar=nVar+1
  VarNames(nVar)=e%VarName
  IF(ASSOCIATED(e%RealArray))  ElemData(nVar,:)=e%RealArray
  IF(ASSOCIATED(e%RealScalar)) ElemData(nVar,:)=e%RealScalar
  IF(ASSOCIATED(e%IntArray))   ElemData(nVar,:)=REAL(e%IntArray)
  IF(ASSOCIATED(e%IntScalar))  ElemData(nVar,:)=REAL(e%IntScalar)
  IF(ASSOCIATED(e%eval))       CALL e%eval(ElemData(nVar,:)) ! function fills elemdata
  e=>e%next
END DO

IF(MPIRoot)THEN
  CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
  CALL WriteAttribute(File_ID,'VarNamesAdd',nVar,StrArray=VarNames)
  CALL CloseDataFile()
END IF
CALL GatheredWriteArray(FileName,create=.FALSE.,&
                        DataSetName='ElemData', rank=2,  &
                        nValGlobal=(/nVar,nGlobalElems/),&
                        nVal=      (/nVar,nElems      /),&
                        offset=    (/0   ,offSetElem  /),&
                        collective=.TRUE.,RealArray=ElemData)
DEALLOCATE(ElemData,VarNames)
END SUBROUTINE WriteAdditionalElemData


!==================================================================================================================================
!> Comparable to WriteAdditionalElemData, but for field data (rank 5 arrays, where the last dimension is 1:nElems)
!> See also general comment of WriteAdditionalElemData.
!> All arrays that are of the same size as the DG solution will be written to a single dataset, since it is a lot faster than
!> writing several datasets. All arrays with a different size will be written separately. Also the optional doSeparateOutput
!> flag can be used to force the output to a separate dataset.
!==================================================================================================================================
SUBROUTINE WriteAdditionalFieldData(FileName,FieldList)
! MODULES
USE MOD_Preproc
USE MOD_Globals
USE MOD_Mesh_Vars,ONLY: offsetElem,nGlobalElems,nElems
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN)      :: FileName  !< Name of the file to be written to
TYPE(tFieldOut),POINTER,INTENT(IN) :: FieldList !< Linked list of arrays to write to file
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255),ALLOCATABLE :: VarNames(:)
REAL,ALLOCATABLE,TARGET        :: tmp(:,:,:,:,:)
REAL,POINTER                   :: NodeData(:,:,:,:,:)
INTEGER                        :: nVar,nVarTotal
TYPE(tFieldOut),POINTER        :: f
!==================================================================================================================================
! TODO: Perform one write for each dataset.
IF(.NOT. ASSOCIATED(FieldList)) RETURN

! Count fixed size and total number of entries
nVar=0
nVarTotal=0
f=>FieldList
DO WHILE(ASSOCIATED(f))
  IF(.NOT.f%doSeparateOutput) nVar=nVar+f%nVal(1)
  nVarTotal=nVarTotal+f%nVal(1)
  f=>f%next
END DO

! --------------------------------------------------------------------------------------------- !
! First the variable size arrays or arrays that should always be written as a separate dataset
! --------------------------------------------------------------------------------------------- !
! Write the attributes
IF(MPIRoot.AND.(nVarTotal.NE.nVar))THEN
  CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
  f=>FieldList
  DO WHILE(ASSOCIATED(f))
  IF(f%doSeparateOutput) CALL WriteAttribute(File_ID,f%DataSetName,f%nVal(1),StrArray=f%VarNames)
    f=>f%next
  END DO
  CALL CloseDataFile()
END IF

! Write the arrays
f=>FieldList
DO WHILE(ASSOCIATED(f))
  IF(f%doSeparateOutput)THEN
    IF(ASSOCIATED(f%RealArray)) THEN ! real array
      NodeData=>f%RealArray
    ELSE IF(ASSOCIATED(f%Eval)) THEN ! eval function
      ALLOCATE(tmp(f%nVal(1),f%nVal(2),f%nVal(3),f%nVal(4),nElems))
      CALL f%eval(tmp)
      NodeData=>tmp
    END IF
    CALL GatheredWriteArray(FileName,create=.FALSE.,&
                            DataSetName=f%DatasetName, rank=5, &
                            nValGlobal=(/f%nVal,nGlobalElems/),&
                            nVal=      (/f%nVal,nElems      /),&
                            offset=    (/0,0,0,0,  offsetElem  /),&
                            collective=.TRUE.,RealArray=NodeData)
    IF(ASSOCIATED(f%Eval)) DEALLOCATE(tmp)
  END IF
  f=>f%next
END DO


! --------------------------------------------------------------------------------------------- !
! Now process arrays with standard size PP_N
! --------------------------------------------------------------------------------------------- !
IF(nVar.LE.0) RETURN ! no standard data present

ALLOCATE(VarNames(nVar))
ALLOCATE(tmp(nVar,0:PP_N,0:PP_N,0:PP_NZ,nElems))

! Write the attributes
IF(MPIRoot)THEN
  nVar=0
  f=>FieldList
  DO WHILE(ASSOCIATED(f))
    IF(.NOT.f%doSeparateOutput)THEN
      VarNames(nVar+1:nVar+f%nVal(1))=f%VarNames
      nVar=nVar+f%nVal(1)
    END IF
    f=>f%next
  END DO
  CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
  CALL WriteAttribute(File_ID,'VarNamesAddField',nVar,StrArray=VarNames)
  CALL CloseDataFile()
END IF

! Collect all fixed size arrays in one array
nVar=0
f=>FieldList
DO WHILE(ASSOCIATED(f))
  IF(.NOT.f%doSeparateOutput)THEN
    IF(ASSOCIATED(f%RealArray))THEN ! real array
      tmp(nVar+1:nVar+f%nVal(1),:,:,:,:)=f%RealArray
    ELSEIF(ASSOCIATED(f%Eval))THEN  ! eval function
      CALL f%Eval(tmp(nVar+1:nVar+f%nVal(1),:,:,:,:))
    END IF
    nVar=nVar+f%nVal(1)
  ENDIF
  f=>f%next
END DO
! Write the arrays (fixed size)
CALL GatheredWriteArray(FileName,create=.FALSE.,&
                        DataSetName='FieldData', rank=5,  &
                        nValGlobal=(/nVar,PP_N+1,PP_N+1,PP_NZ+1,nGlobalElems/),&
                        nVal=      (/nVar,PP_N+1,PP_N+1,PP_NZ+1,nElems      /),&
                        offset=    (/0   ,0     ,0     ,0     ,offsetElem  /),&
                        collective=.TRUE.,RealArray=tmp)
DEALLOCATE(VarNames,tmp)

END SUBROUTINE WriteAdditionalFieldData


!==================================================================================================================================
!> Subroutine to write the baseflow to HDF5 format
!==================================================================================================================================
SUBROUTINE WriteBaseflow(MeshFileName,OutputTime)
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Output_Vars  ,ONLY: ProjectName
USE MOD_Mesh_Vars    ,ONLY: offsetElem,nGlobalElems,nElems
USE MOD_Sponge_Vars  ,ONLY: SpBaseFlow
USE MOD_Equation_Vars,ONLY: StrVarNames
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)    :: MeshFileName       !< Name of mesh file
REAL,INTENT(IN)                :: OutputTime         !< Time of output
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)             :: FileName
REAL                           :: StartT,EndT
REAL,POINTER                   :: UOut(:,:,:,:,:)
INTEGER                        :: NZ_loc
#if PP_dim == 2
INTEGER                        :: iElem,i,j,iVar
#endif
!==================================================================================================================================
IF(MPIROOT)THEN
  WRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' WRITE BASE FLOW TO HDF5 FILE...'
  GETTIME(StartT)
END IF

! Generate skeleton for the file with all relevant data on a single proc (MPIRoot)
FileName=TRIM(TIMESTAMP(TRIM(ProjectName)//'_BaseFlow',OutputTime))//'.h5'
IF(MPIRoot) CALL GenerateFileSkeleton(TRIM(FileName),'BaseFlow',PP_nVar,PP_N,StrVarNames,MeshFileName,OutputTime)

#if PP_dim == 3
  UOut => SpBaseFlow
  NZ_loc=PP_N
#else
IF (.NOT.output2D) THEN
  ALLOCATE(UOut(PP_nVar,0:PP_N,0:PP_N,0:PP_N,nElems))
  DO iElem=1,nElems
    DO j=0,PP_N; DO i=0,PP_N
      DO iVar=1,PP_nVar
        UOut(iVar,i,j,:,iElem)=SpBaseFlow(iVar,i,j,0,iElem)
      END DO ! iVar=1,PP_nVar
    END DO; END DO
  END DO
  NZ_loc=PP_N
ELSE
  UOut => SpBaseFlow
  NZ_loc=0
END IF
#endif

! Write DG solution
#if USE_MPI
CALL MPI_BARRIER(MPI_COMM_FLEXI,iError)
#endif
CALL GatheredWriteArray(FileName,create=.FALSE.,&
                        DataSetName='DG_Solution', rank=5,&
                        nValGlobal=(/PP_nVar,PP_N+1,PP_N+1,NZ_loc+1,nGlobalElems/),&
                        nVal=      (/PP_nVar,PP_N+1,PP_N+1,NZ_loc+1,nElems/),&
                        offset=    (/0,      0,     0,     0,     offsetElem/),&
                        collective=.TRUE., RealArray=UOut)

#if PP_dim == 2
IF(.NOT.output2D) DEALLOCATE(UOut)
#endif
IF(MPIRoot)THEN
  CALL MarkWriteSuccessfull(FileName)
  GETTIME(EndT)
  WRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')'DONE  [',EndT-StartT,'s]'
END IF
END SUBROUTINE WriteBaseflow


!==================================================================================================================================
!> Subroutine to write time averaged data and fluctuations HDF5 format
!==================================================================================================================================
SUBROUTINE WriteTimeAverage(MeshFileName,OutputTime,dtAvg,FV_Elems_In,nVal,&
                            nVarAvg,VarNamesAvg,UAvg,&
                            nVarFluc,VarNamesFluc,UFluc,&
                            FileName_In,FutureTime)
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Output_Vars,ONLY: ProjectName
USE MOD_Mesh_Vars  ,ONLY: offsetElem,nGlobalElems,nElems
USE MOD_2D         ,ONLY: ExpandArrayTo3D
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)             :: nVarAvg                                      !< Dimension of UAvg
INTEGER,INTENT(IN)             :: nVarFluc                                     !< Dimension of UAvg
INTEGER,INTENT(IN)             :: nVal(3)                                      !< Dimension of UAvg
INTEGER,INTENT(IN)             :: FV_Elems_In(nElems)                          !< Array with custom FV_Elem information
CHARACTER(LEN=*),INTENT(IN)    :: MeshFileName                                 !< Name of mesh file
CHARACTER(LEN=255),INTENT(IN)  :: VarNamesAvg(nVarAvg)                         !< Average variable names
CHARACTER(LEN=255),INTENT(IN)  :: VarNamesFluc(nVarFluc)                       !< Average variable names
REAL,INTENT(IN)                :: OutputTime                                   !< Time of output
REAL,INTENT(IN)                :: dtAvg                                        !< Timestep of averaging
REAL,INTENT(IN),TARGET         :: UAvg(nVarAvg,nVal(1),nVal(2),nVal(3),nElems) !< Averaged Solution
REAL,INTENT(IN),TARGET         :: UFluc(nVarFluc,nVal(1),nVal(2),nVal(3),nElems) !< Averaged Solution
REAL,INTENT(IN),OPTIONAL       :: FutureTime                                   !< Time of next output
CHARACTER(LEN=*),INTENT(IN),OPTIONAL :: Filename_In                            !< custom filename
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)             :: FileName,DataSet,tmp255
REAL                           :: StartT,EndT
REAL,POINTER                   :: UOut(:,:,:,:,:)
#if PP_dim == 2
REAL,POINTER                   :: UOut2D(:,:,:,:,:)
#endif
TYPE(tElementOut),POINTER      :: ElementOutTimeAvg
INTEGER                        :: nVar_loc, nVal_loc(5), nVal_glob(5), i
!==================================================================================================================================
IF(ANY(nVal(1:PP_dim).EQ.0)) RETURN ! no time averaging
IF(nVarAvg.EQ.0.AND.nVarFluc.EQ.0) RETURN ! no time averaging
IF(MPIROOT)THEN
  WRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' WRITE TIME AVERAGED STATE TO HDF5 FILE...'
  GETTIME(StartT)
END IF

! Generate skeleton for the file with all relevant data on a single proc (MPIRoot)
FileName=TRIM(TIMESTAMP(TRIM(ProjectName)//'_TimeAvg',OutputTime))//'.h5'
IF(PRESENT(Filename_In)) Filename=TRIM(Filename_In)

! Write time averaged data --------------------------------------------------------------------------------------------------------
IF(MPIRoot)THEN
                    tmp255 = TRIM('DUMMY_DO_NOT_VISUALIZE')
                    CALL GenerateFileSkeleton(TRIM(FileName),'TimeAvg',1 ,PP_N,(/tmp255/),&
                           MeshFileName,OutputTime,FutureTime,create=.TRUE.) ! dummy DG_Solution to fix Posti error, tres oegly !!!
  IF(nVarAvg .GT.0) CALL GenerateFileSkeleton(TRIM(FileName),'TimeAvg',nVarAvg ,PP_N,VarNamesAvg,&
                           MeshFileName,OutputTime,FutureTime,create=.FALSE.,Dataset='Mean')
  IF(nVarFluc.GT.0) CALL GenerateFileSkeleton(TRIM(FileName),'TimeAvg',nVarFluc,PP_N,VarNamesFluc,&
                           MeshFileName,OutputTime,FutureTime,create=.FALSE.,Dataset='MeanSquare')

  CALL OpenDataFile(TRIM(FileName),create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
  CALL WriteAttribute(File_ID,'AvgTime',1,RealScalar=dtAvg)
  CALL CloseDataFile()
END IF
#if USE_MPI
CALL MPI_BARRIER(MPI_COMM_FLEXI,iError)
#endif

! write dummy FV array
NULLIFY(ElementOutTimeAvg)
CALL AddToElemData(ElementOutTimeAvg,'FV_Elems',IntArray=FV_Elems_In)
CALL WriteAdditionalElemData(FileName,ElementOutTimeAvg)
DEALLOCATE(ElementOutTimeAvg)

DO i=1,2
  nVar_loc =  MERGE(nVarAvg,nVarFluc,i.EQ.1)
  IF(nVar_loc.EQ.0) CYCLE
  DataSet  =  MERGE('Mean      ','MeanSquare',i.EQ.1)
  IF(i.EQ.1)THEN
    UOut   => UAvg
  ELSE
    UOut   => UFluc
  END IF
  nVal_loc =  (/nVar_loc,nVal,nElems/)
#if PP_dim == 2
  IF (.NOT.output2D) THEN
    ! If the output should be done with a full third dimension in a two dimensional computation, we need to expand the solution
    NULLIFY(UOut2D)
    ALLOCATE(UOut2D(nVal_loc(1),nVal_loc(2),nVal_loc(3),nVal(1),nVal_loc(5)))
    CALL ExpandArrayTo3D(5,nVal_loc,4,nVal(1),UOut,UOut2D)
    nVal_loc(4)=nVal(1)
    UOut=>UOut2D
  END IF
#endif
  nVal_glob=  (/nVal_loc(1:4),nGlobalElems/)

  ! Reopen file and write DG solution
  CALL GatheredWriteArray(FileName,create=.FALSE.,&
                          DataSetName=TRIM(DataSet), rank=5,&
                          nValGlobal=nVal_glob,&
                          nVal=      nVal_loc,&
                          offset=    (/0,0,0,0,offsetElem/),&
                          collective=.TRUE., RealArray=UOut)
#if PP_dim == 2
  ! Deallocate UOut only if we did not point to UAvg
  IF(.NOT.output2D) DEALLOCATE(UOut2D)
#endif
END DO

IF(MPIROOT) CALL MarkWriteSuccessfull(FileName)

IF(MPIROOT)THEN
  GETTIME(EndT)
  WRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')'DONE  [',EndT-StartT,'s]'
END IF
END SUBROUTINE WriteTimeAverage


!==================================================================================================================================
!> Subroutine that generates the output file on a single processor and writes all the necessary attributes (better MPI performance)
!==================================================================================================================================
SUBROUTINE GenerateFileSkeleton(FileName,TypeString,nVar,NData,StrVarNames,MeshFileName,OutputTime,&
                                FutureTime,Dataset,create,withUserblock)
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Output_Vars        ,ONLY: ProjectName,UserBlockTmpFile,userblock_total_len
USE MOD_Mesh_Vars          ,ONLY: nGlobalElems
USE MOD_Interpolation_Vars ,ONLY: NodeType
#if FV_ENABLED
USE MOD_FV_Vars            ,ONLY: FV_X,FV_w
#endif
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)    :: FileName           !< Name of file to create
CHARACTER(LEN=*),INTENT(IN)    :: TypeString         !< Type of file to be created (state,timeaverage etc.)
INTEGER,INTENT(IN)             :: nVar               !< Number of variables
INTEGER,INTENT(IN)             :: NData              !< Polynomial degree of data
CHARACTER(LEN=255),INTENT(IN)  :: StrVarNames(nVar)  !< Variabel names
CHARACTER(LEN=*),INTENT(IN)    :: MeshFileName       !< Name of mesh file
REAL,INTENT(IN)                :: OutputTime         !< Time of output
REAL,INTENT(IN),OPTIONAL       :: FutureTime         !< Time of next output
CHARACTER(LEN=*),INTENT(IN),OPTIONAL :: Dataset      !< Name of the dataset
LOGICAL,INTENT(IN),OPTIONAL    :: create             !< specify whether file should be newly created
LOGICAL,INTENT(IN),OPTIONAL    :: withUserblock      !< specify whether userblock data shall be written or not
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER(HID_T)                 :: DSet_ID,FileSpace,HDF5DataType
INTEGER(HSIZE_T)               :: Dimsf(5)
CHARACTER(LEN=255)             :: MeshFile255
CHARACTER(LEN=255)             :: tmp255
CHARACTER(LEN=255)             :: Dataset_Str,Varname_Str
#if FV_ENABLED
REAL                           :: FV_w_array(0:PP_N)
#endif
LOGICAL                        :: withUserblock_loc,create_loc
!==================================================================================================================================
! Create file
create_loc=.TRUE.
withUserblock_loc=.FALSE.
IF(PRESENT(create))                       create_loc       =create
IF(PRESENT(withUserblock).AND.create_loc) withUserblock_loc=withUserblock
Dataset_Str='DG_Solution'
Varname_Str='VarNames'
IF(PRESENT(Dataset))THEN
  Dataset_Str=TRIM(Dataset)
  Varname_Str='VarNames_'//TRIM(DataSet)
END IF

CALL OpenDataFile(TRIM(FileName),create=create_loc,single=.TRUE.,readOnly=.FALSE.,&
                  userblockSize=MERGE(userblock_total_len,0,withUserblock_loc))

! Preallocate the data space for the dataset.
IF(output2D) THEN
  Dimsf=(/nVar,NData+1,NData+1,1,nGlobalElems/)
ELSE
  Dimsf=(/nVar,NData+1,NData+1,NData+1,nGlobalElems/)
END IF

CALL H5SCREATE_SIMPLE_F(5, Dimsf, FileSpace, iError)
! Create the dataset with default properties.
HDF5DataType=H5T_NATIVE_DOUBLE
CALL H5DCREATE_F(File_ID,TRIM(Dataset_Str), HDF5DataType, FileSpace, DSet_ID, iError)
! Close the filespace and the dataset
CALL H5DCLOSE_F(Dset_id, iError)
CALL H5SCLOSE_F(FileSpace, iError)
CALL WriteAttribute(File_ID,TRIM(Varname_Str),nVar,StrArray=StrVarNames(1:nVar))

! Write default attributes only if file is created
IF(create_loc)THEN

  ! Write file header
  CALL WriteHeader(TRIM(TypeString),File_ID)

  ! Write dataset properties "Time","MeshFile","NextFile","NodeType","VarNames"
  CALL WriteAttribute(File_ID,'N',1,IntScalar=PP_N)
  CALL WriteAttribute(File_ID,'Dimension',1,IntScalar=PP_dim)
  CALL WriteAttribute(File_ID,'Time',1,RealScalar=OutputTime)
  tmp255=TRIM(MeshFileName)
  CALL WriteAttribute(File_ID,'MeshFile',1,StrScalar=(/tmp255/))
  IF(PRESENT(FutureTime))THEN
    MeshFile255=TRIM(TIMESTAMP(TRIM(ProjectName)//'_'//TRIM(TypeString),FutureTime))//'.h5'
    CALL WriteAttribute(File_ID,'NextFile',1,StrScalar=(/MeshFile255/))
  END IF
  tmp255=TRIM(NodeType)
  CALL WriteAttribute(File_ID,'NodeType',1,StrScalar=(/tmp255/))
#if FV_ENABLED
  CALL WriteAttribute(File_ID,'FV_Type',1,IntScalar=2)
  CALL WriteAttribute(File_ID,'FV_X',PP_N+1,RealArray=FV_X)
  FV_w_array(:)= FV_w
  CALL WriteAttribute(File_ID,'FV_w',PP_N+1,RealArray=FV_w_array)
#endif

  CALL WriteAttribute(File_ID,'NComputation',1,IntScalar=PP_N)
END IF

CALL CloseDataFile()

! Add userblock to hdf5-file (only if create)
IF(withUserblock_loc) CALL copy_userblock(TRIM(FileName)//C_NULL_CHAR,TRIM(UserblockTmpFile)//C_NULL_CHAR)

END SUBROUTINE GenerateFileSkeleton


!==================================================================================================================================
!> Add time attribute, after all relevant data has been written to a file,
!> to indicate the writing process has been finished successfully
!==================================================================================================================================
SUBROUTINE MarkWriteSuccessfull(FileName)
! MODULES
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)    :: FileName           !< Name of the file
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: Time(8)
!==================================================================================================================================
CALL OpenDataFile(TRIM(FileName),create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
CALL DATE_AND_TIME(VALUES=time)
CALL WriteAttribute(File_ID,'TIME',8,IntArray=time)
CALL CloseDataFile()
END SUBROUTINE MarkWriteSuccessfull


!==================================================================================================================================
!> Deletes all HDF5 output files, beginning from time Flushtime. Used for cleanup at the beginning of a new simulation
!==================================================================================================================================
SUBROUTINE FlushFiles(FlushTime_In)
! MODULES
USE MOD_Globals
USE MOD_Output_Vars ,ONLY: ProjectName
USE MOD_HDF5_Input  ,ONLY: GetNextFileName
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
REAL,INTENT(IN),OPTIONAL :: FlushTime_In     !< Time to start flush
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                  :: stat,ioUnit
REAL                     :: FlushTime
CHARACTER(LEN=255)       :: FileName,InputFile,NextFile
!==================================================================================================================================
IF(.NOT.MPIRoot) RETURN

SWRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' DELETING OLD HDF5 FILES...'
IF (.NOT.PRESENT(FlushTime_In)) THEN
  FlushTime=0.0
ELSE
  FlushTime=FlushTime_In
END IF
FileName=TRIM(TIMESTAMP(TRIM(ProjectName)//'_State',FlushTime))//'.h5'

! Delete state files
InputFile=TRIM(FileName)
! Read calculation time from file
CALL GetNextFileName(Inputfile,NextFile,.TRUE.)
! Delete File - only root
stat=0
OPEN ( NEWUNIT= ioUnit,         &
       FILE   = InputFile,      &
       STATUS = 'OLD',          &
       ACTION = 'WRITE',        &
       ACCESS = 'SEQUENTIAL',   &
       IOSTAT = stat          )
IF(stat .EQ. 0) CLOSE ( ioUnit,STATUS = 'DELETE' )
DO
  InputFile=TRIM(NextFile)
  ! Read calculation time from file
  CALL GetNextFileName(Inputfile,NextFile,.TRUE.)
  ! Delete File - only root
  stat=0
  OPEN ( NEWUNIT= ioUnit,         &
         FILE   = InputFile,      &
         STATUS = 'OLD',          &
         ACTION = 'WRITE',        &
         ACCESS = 'SEQUENTIAL',   &
         IOSTAT = stat          )
  IF(stat .EQ. 0) CLOSE ( ioUnit,STATUS = 'DELETE' )
  IF(iError.NE.0) EXIT  ! iError is set in GetNextFileName !
END DO

WRITE(UNIT_stdOut,'(a)',ADVANCE='YES')'DONE'

END SUBROUTINE FlushFiles


!==================================================================================================================================
!> Subroutine to write a distinct file header to each HDF5 file
!==================================================================================================================================
SUBROUTINE WriteHeader(FileType_in,File_ID)
! MODULES
USE MOD_Output_Vars,ONLY:ProgramName,FileVersion,ProjectName
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)              :: FileType_in   !< Type of file (e.g. state, timeaverage)
INTEGER(HID_T),INTENT(IN)                :: File_ID       !< HDF5 file id
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255) :: tmp255
!==================================================================================================================================
! Write a small file header to identify a Flexi HDF5 files
! Attributes are program name, file type identifier, project name and version number
tmp255=TRIM(ProgramName)
CALL WriteAttribute(File_ID,'Program'     ,1,StrScalar=(/tmp255/))
tmp255=TRIM(FileType_in)
CALL WriteAttribute(File_ID,'File_Type'   ,1,StrScalar=(/tmp255/))
tmp255=TRIM(ProjectName)
CALL WriteAttribute(File_ID,'Project_Name',1,StrScalar=(/tmp255/))
CALL WriteAttribute(File_ID,'File_Version',1,RealScalar=FileVersion)
END SUBROUTINE WriteHeader



!==================================================================================================================================
!> Subroutine to write Attributes to HDF5 format of a given Loc_ID, which can be the File_ID,datasetID,groupID. This must be opened
!> outside of the routine. If you directly want to write an attribute to a dataset, just provide the name of the dataset
!==================================================================================================================================
SUBROUTINE WriteAttribute(Loc_ID_in,AttribName,nVal,DataSetname,&
                          RealScalar,IntScalar,StrScalar,LogicalScalar, &
                          RealArray,IntArray,StrArray)
! MODULES
USE MOD_Globals
USE,INTRINSIC :: ISO_C_BINDING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER(HID_T)    ,INTENT(IN)           :: Loc_ID_in              !< Dataset ID (only if already open)
CHARACTER(LEN=*)  ,INTENT(IN)           :: AttribName             !< name of the attribute to be written
INTEGER           ,INTENT(IN)           :: nVal                   !< number of array entries if array is written
CHARACTER(LEN=255),INTENT(IN),OPTIONAL        :: DatasetName      !< name of the dataset created
REAL              ,INTENT(IN),OPTIONAL,TARGET :: RealScalar       !< real scalar
INTEGER           ,INTENT(IN),OPTIONAL,TARGET :: IntScalar        !< integer scalar
CHARACTER(LEN=255),INTENT(IN),OPTIONAL,TARGET :: StrScalar(1)     !< scalar string
LOGICAL           ,INTENT(IN),OPTIONAL        :: LogicalScalar    !< logical scalar
REAL              ,INTENT(IN),OPTIONAL,TARGET :: RealArray(nVal)  !< real array of length nVal
INTEGER           ,INTENT(IN),OPTIONAL,TARGET :: IntArray(nVal)   !< integer array of length nVal
CHARACTER(LEN=255),INTENT(IN),OPTIONAL,TARGET :: StrArray(nVal)   !< string array of length nVal
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: Rank
INTEGER(HID_T)                 :: DataSpace,Attr_ID,Loc_ID,Type_ID
INTEGER(HSIZE_T), DIMENSION(1) :: Dimsf
INTEGER(SIZE_T)                :: AttrLen
INTEGER,TARGET                 :: logtoint
TYPE(C_PTR)                    :: buf
INTEGER                        :: hdferr
!==================================================================================================================================
LOGWRITE(*,*)' WRITE ATTRIBUTE "',TRIM(AttribName),'" TO HDF5 FILE...'
IF(PRESENT(DataSetName))THEN
  ! Open dataset
  IF(TRIM(DataSetName).NE.'') CALL H5DOPEN_F(File_ID, TRIM(DatasetName),Loc_ID, iError)
ELSE
  Loc_ID=Loc_ID_in
END IF
! Create scalar data space for the attribute.
Rank=1
Dimsf(:)=0 !???
Dimsf(1)=nVal
CALL H5SCREATE_SIMPLE_F(Rank, Dimsf, DataSpace, iError)
! Create the attribute for group Loc_ID.
IF(PRESENT(RealScalar)) Type_ID=H5T_NATIVE_DOUBLE
IF(PRESENT(RealArray))  Type_ID=H5T_NATIVE_DOUBLE
IF(PRESENT(IntScalar))  Type_ID=H5T_NATIVE_INTEGER
IF(PRESENT(IntArray))   Type_ID=H5T_NATIVE_INTEGER
IF(PRESENT(LogicalScalar))THEN
  LogToInt=MERGE(1,0,LogicalScalar)
  Type_ID=H5T_NATIVE_INTEGER
END IF

! Create character string datatype for the attribute.
! For a attribute character, we have to build our own type with corresponding attribute length
IF(PRESENT(StrScalar))THEN
  AttrLen=LEN_TRIM(StrScalar(1))
  CALL H5TCOPY_F(H5T_NATIVE_CHARACTER, Type_ID, iError)
  CALL H5TSET_SIZE_F(Type_ID, AttrLen, iError)
END IF
IF(PRESENT(StrArray))THEN
  AttrLen=255
  CALL H5TCOPY_F(H5T_NATIVE_CHARACTER, Type_ID, iError)
  CALL H5TSET_SIZE_F(Type_ID, AttrLen, iError)
ENDIF

CALL H5ESET_AUTO_F(0, hdferr)
CALL H5AOPEN_F(    Loc_ID, TRIM(AttribName), Attr_ID, iError)
IF(iError.EQ.0)THEN
  CALL H5ACLOSE_F(Attr_ID, iError)
  CALL H5ADELETE_F(Loc_ID, TRIM(AttribName)         , iError)
END IF
CALL H5ESET_AUTO_F(1, hdferr)
CALL H5ACREATE_F(Loc_ID, TRIM(AttribName), Type_ID, DataSpace, Attr_ID, iError)
IF(iError.NE.0) STOP 'Could not open or create attribute!'

! Write the attribute data.
buf=C_NULL_PTR
IF(PRESENT(RealArray))     buf=C_LOC(RealArray)
IF(PRESENT(RealScalar))    buf=C_LOC(RealScalar)
IF(PRESENT(IntArray))      buf=C_LOC(IntArray)
IF(PRESENT(IntScalar))     buf=C_LOC(IntScalar)
IF(PRESENT(LogicalScalar)) buf=C_LOC(LogToInt)
IF(PRESENT(StrScalar))     buf=C_LOC(StrScalar(1))
IF(PRESENT(StrArray))      buf=C_LOC(StrArray(1))
IF(C_ASSOCIATED(buf))&
  CALL H5AWRITE_F(Attr_ID, Type_ID, buf, iError)

! Close datatype
IF(PRESENT(StrScalar).OR.PRESENT(StrArray)) CALL H5TCLOSE_F(Type_ID, iError)
! Close dataspace
CALL H5SCLOSE_F(DataSpace, iError)
! Close the attribute.
CALL H5ACLOSE_F(Attr_ID, iError)
IF(Loc_ID.NE.Loc_ID_in)THEN
  ! Close the dataset and property list.
  CALL H5DCLOSE_F(Loc_ID, iError)
END IF
LOGWRITE(*,*)'...DONE!'
END SUBROUTINE WriteAttribute


#if USE_PARTICLES
!===================================================================================================================================
! Subroutine that write the particle information to the state file
!> PartInt  contains the index of particles in each global element
!> PartData contains the indidividual properties of each particle
!===================================================================================================================================
SUBROUTINE WriteParticle(FileName)
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Mesh_Vars,             ONLY: nGlobalElems, offsetElem
USE MOD_Part_Tools,            ONLY: UpdateNextFreePosition
USE MOD_Particle_Globals
USE MOD_Particle_Analyze_Vars, ONLY: PartPath,doParticleDispersionTrack,doParticlePathTrack
USE MOD_Particle_Boundary_Vars,ONLY: doParticleReflectionTrack
USE MOD_Particle_HDF5_Output
USE MOD_Particle_Vars,         ONLY: PDM,PEM,PartState,PartSpecies,PartReflCount,PartIndex
USE MOD_Particle_Vars,         ONLY: useLinkedList,doPartIndex
#if USE_MPI
USE MOD_Particle_MPI_Vars,     ONLY: PartMPI
#endif /*MPI*/
#if CODE_ANALYZE
USE MOD_Particle_Tracking_Vars,ONLY: PartOut,MPIRankOut
#endif /*CODE_ANALYZE*/
! Particle turbulence models
USE MOD_Particle_Vars,         ONLY: TurbPartState
USE MOD_Particle_SGS_Vars,     ONLY: nSGSVars
#if USE_RW
USE MOD_Particle_RandomWalk_Vars,ONLY: nRWVars
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN)  :: FileName
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255),ALLOCATABLE :: StrVarNames(:)
INTEGER                        :: nVar,VarShift
#if USE_MPI
INTEGER                        :: sendbuf(2),recvbuf(2)
INTEGER                        :: nParticles(0:nProcessors-1)
#endif
LOGICAL                        :: reSwitch
INTEGER                        :: pcount
INTEGER                        :: locnPart,offsetnPart
INTEGER                        :: iPart,nPart_glob,iElem
INTEGER,ALLOCATABLE            :: PartInt(:,:)
REAL,ALLOCATABLE               :: PartData(:,:)
INTEGER,PARAMETER              :: PartIntSize=2      !number of entries in each line of PartInt
INTEGER                        :: PartDataSize       !number of entries in each line of PartData
INTEGER                        :: locnPart_max, tmpIndex
! Particle turbulence models
INTEGER                        :: TurbPartDataSize
REAL,ALLOCATABLE               :: TurbPartData(:,:)
!===================================================================================================================================

! Size and location of particle data
PartDataSize = 7
tmpIndex     = 8
! Increase size if index is tracked
IF (doPartIndex) THEN
  PartDataSize = PartDataSize + 1
  tmpIndex     = tmpIndex     + 1
END IF
varShift     = 0
! Increase size if reflections are tracked
IF (doParticleReflectionTrack) THEN
  PartDataSize = PartDataSize + 1
  varShift     = 1
END IF
! Incresse size if the absolute particle path is tracked
IF (doParticleDispersionTrack.OR.doParticlePathTrack) &
  PartDataSize = PartDataSize + 3

! Add turbulent dispersion data to output
IF (ALLOCATED(TurbPartState)) THEN
  TurbPartDataSize = nSGSVars
#if USE_RW
  TurbPartDataSize = TurbPartDataSize + nRWVars
#endif
END IF

! Determine number of particles in the complete domain
locnPart =   0
!>> Count number of particle on local proc
DO pcount = 1,PDM%ParticleVecLength
  IF(PDM%ParticleInside(pcount)) THEN
    locnPart = locnPart + 1
  END IF
END DO

#if USE_MPI
!>> Sum up particles from the other procs
sendbuf(1)  = locnPart
recvbuf     = 0
CALL MPI_EXSCAN(sendbuf(1),recvbuf(1),1,MPI_INTEGER,MPI_SUM,MPI_COMM_FLEXI,iError)
!>> Offset of each proc is the sum of the particles on the previous procs
offsetnPart = recvbuf(1)
sendbuf(1)  = recvbuf(1)+locnPart
!>> Last proc knows the global number
CALL MPI_BCAST(sendbuf(1),1,MPI_INTEGER,nProcessors-1,MPI_COMM_FLEXI,iError)
!>> Gather the global number and communicate to root (MPIRank.EQ.0)
nPart_glob  = sendbuf(1)
CALL MPI_GATHER(locnPart,1,MPI_INTEGER,nParticles,1,MPI_INTEGER,0,MPI_COMM_FLEXI,iError)
LOGWRITE(*,*)'offsetnPart,locnPart,nPart_glob',offsetnPart,locnPart,nPart_glob
CALL MPI_REDUCE(locnPart, locnPart_max, 1, MPI_INTEGER, MPI_MAX, 0, MPI_COMM_FLEXI, IERROR)
#else
offsetnPart  = 0
nPart_glob   = locnPart
locnPart_max = locnPart
#endif

! Allocate data arrays for mean particle quantities
ALLOCATE(PartInt( PartIntSize ,offsetElem+1 :offsetElem+PP_nElems))
ALLOCATE(PartData(PartDataSize,offsetnPart+1:offsetnPart+locnPart))
! Allocate data arrays for turbulent particle quantities
IF (ALLOCATED(TurbPartState)) ALLOCATE(TurbPartData(TurbPartDataSize,offsetnPart+1:offsetnPart+locnPart))

! Update next free position using a linked list
ALLOCATE(PEM%pStart (offsetElem+1:offsetElem+PP_nElems) , &
         PEM%pNumber(offsetElem+1:offsetElem+PP_nElems) , &
         PEM%pNext  (1           :PDM%maxParticleNumber), &
         PEM%pEnd   (offsetElem+1:offsetElem+PP_nElems))
useLinkedList = .TRUE.
CALL UpdateNextFreePosition()

! Walk along the linked list and fill the data arrays
iPart = offsetnPart
! Walk over all elements on local proc
DO iElem = offsetElem+1,offsetElem+PP_nElems
  ! Set start of particle numbers in current element
  PartInt(1,iElem) = iPart
  ! Find all particles in current element
  IF (ALLOCATED(PEM%pNumber)) THEN
    PartInt(2,iElem) = PartInt(1,iElem) + PEM%pNumber(iElem)
    ! Sum up particles and add properties to output array
    pcount = PEM%pStart(iElem)
    DO iPart = PartInt(1,iElem)+1,PartInt(2,iElem)
      PartData(1:6,iPart) = PartState(1:6,pcount)
      PartData(7  ,iPart) = REAL(PartSpecies(pcount))
      IF (doPartIndex)                                      PartData(8                                    ,iPart) = REAL(PartIndex(pcount))
      IF (doParticleReflectionTrack)                        PartData(tmpIndex                             ,iPart) = REAL(PartReflCount(pcount))
      IF (doParticleDispersionTrack.OR.doParticlePathTrack) PartData(tmpIndex+varShift:tmpIndex+2+varShift,iPart) = PartPath(1:3,pcount)

      ! Turbulent particle properties
      IF (ALLOCATED(TurbPartState))  TurbPartData(:,iPart)=TurbPartState(:,pcount)

      ! Set the index to the next particle
      pcount = PEM%pNext(pcount)
    END DO
    ! Set counter to the end of particle number in the current element
    iPart = PartInt(2,iElem)
  ELSE
    CALL abort(__STAMP__, " Particle HDF5-Output method not supported! PEM%pNumber not associated")
  END IF
  PartInt(2,iElem)=iPart
END DO ! iElem = offsetElem+1,offsetElem+PP_nElems

! Allocate PartInt varnames array and fill it
nVar=2
ALLOCATE(StrVarNames(nVar))
StrVarNames(1)='FirstPartID'
StrVarNames(2)='LastPartID'

IF(MPIRoot)THEN
  CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
  CALL WriteAttribute(File_ID,'VarNamesPartInt',nVar,StrArray=StrVarNames)
  CALL CloseDataFile()
END IF

reSwitch=.FALSE.
IF(gatheredWrite)THEN
  ! gatheredwrite not working with distributed particles
  ! particles require own routine for which the communicator has to be build each time
  reSwitch=.TRUE.
  gatheredWrite=.FALSE.
END IF

! Associate construct for integer KIND=8 possibility
ASSOCIATE (&
      nGlobalElems    => INT(nGlobalElems)                              ,&
      nVar            => INT(nVar)                                      ,&
      PP_nElems       => INT(PP_nElems)                                 ,&
      offsetElem      => INT(offsetElem)                                ,&
      PartDataSize    => INT(PartDataSize))

  CALL GatheredWriteArray(FileName                                      ,&
                          create      = .FALSE.                         ,&
                          DataSetName = 'PartInt'                       ,&
                          rank        = 2                               ,&
                          nValGlobal  = (/nVar,nGlobalElems/)           ,&
                          nVal        = (/nVar,PP_nElems   /)           ,&
                          offset      = (/0   ,offsetElem  /)           ,&
                          collective  = .TRUE.                          ,&
                          IntArray    = PartInt)
  DEALLOCATE(StrVarNames)

  ! Allocate PartData varnames array and fill it
  ALLOCATE(StrVarNames(PartDataSize))
  StrVarNames(1:3) = (/'ParticlePositionX','ParticlePositionY','ParticlePositionZ'/)
  StrVarNames(4:6) = (/'VelocityX'        ,'VelocityY'        ,'VelocityZ'        /)
  StrVarNames(7)   = 'Species'
  IF(doPartIndex) StrVarNames(8)   = 'Index'
  IF (doParticleReflectionTrack) &
    StrVarNames(tmpIndex) = 'ReflectionCount'
  IF (doParticleDispersionTrack.OR.doParticlePathTrack) &
    StrVarNames(tmpIndex+varShift:tmpIndex+2+varShift)=(/'PartPathX','PartPathY','PartPathZ'/)

  IF(MPIRoot)THEN
    CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
    CALL WriteAttribute(File_ID,'VarNamesParticles',PartDataSize,StrArray=StrVarNames)
    CALL CloseDataFile()
  END IF

#if USE_MPI
 CALL DistributedWriteArray(FileName                                    ,&
                            DataSetName  = 'PartData'                   ,&
                            rank         = 2                            ,&
                            nValGlobal   = (/PartDataSize,nPart_glob /) ,&
                            nVal         = (/PartDataSize,locnPart   /) ,&
                            offset       = (/0           ,offsetnPart/) ,&
                            collective   =.FALSE.                       ,&
                            offSetDim    = 2                            ,&
                            communicator = PartMPI%COMM                 ,&
                            RealArray    = PartData)
#else
  CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
  CALL WriteArray(          DataSetName  = 'PartData'                   ,&
                            rank         = 2                            ,&
                            nValGlobal   = (/PartDataSize,nPart_glob /) ,&
                            nVal         = (/PartDataSize,locnPart   /) ,&
                            offset       = (/0           ,offsetnPart/) ,&
                            collective   = .TRUE.                       ,&
                            RealArray    = PartData)
  CALL CloseDataFile()
#endif /*MPI*/

  ! Turbulent particle properties currently not supported to be read directly. Do not associate varnames
#if USE_MPI
  IF (ALLOCATED(TurbPartState)) &
    CALL DistributedWriteArray(FileName                                        ,&
                               DataSetName  = 'TurbPartData'                   ,&
                               rank         = 2                                ,&
                               nValGlobal   = (/TurbPartDataSize,nPart_glob /) ,&
                               nVal         = (/TurbPartDataSize,locnPart   /) ,&
                               offset       = (/0               ,offsetnPart/) ,&
                               collective   = .FALSE.                          ,&
                               offSetDim    = 2                                ,&
                               communicator = PartMPI%COMM                     ,&
                               RealArray    = TurbPartData)
#else
  IF (ALLOCATED(TurbPartState)) THEN
    CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
    CALL WriteArray(           DataSetName  = 'TurbPartData'                   ,&
                               rank         = 2                                ,&
                               nValGlobal   = (/TurbPartDataSize,nPart_glob/)  ,&
                               nVal         = (/TurbPartDataSize,locnPart/)    ,&
                               offset       = (/0               ,offsetnPart/) ,&
                               collective   = .TRUE.                           ,&
                               RealArray    = PartData)
    CALL CloseDataFile()
  END IF
#endif /*MPI*/

END ASSOCIATE
  ! reswitch
IF(reSwitch) gatheredWrite=.TRUE.

! De-allocate linked list and return to normal particle array mode
useLinkedList=.FALSE.
DEALLOCATE( StrVarNames  &
          , PartInt      &
          , PartData     &
          , PEM%pStart   &
          , PEM%pNumber  &
          , PEM%pNext    &
          , PEM%pEnd)

END SUBROUTINE WriteParticle
#endif /*PARTICLES*/

END MODULE MOD_HDF5_output
