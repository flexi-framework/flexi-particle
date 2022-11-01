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
MODULE MOD_HDF5_Output_State
! MODULES
USE MOD_IO_HDF5
USE MOD_HDF5_Output
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------

INTERFACE WriteState
  MODULE PROCEDURE WriteState
END INTERFACE

PUBLIC :: WriteState
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
#if USE_PARTICLES
USE MOD_Particle_HDF5_Output,ONLY: WriteParticle
#endif /*USE_PARTICLES*/
#if USE_LOADBALANCE
USE MOD_Particle_HDF5_Output,ONLY: WriteElemTime
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
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

GETTIME(StartT)
SWRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' WRITE STATE TO HDF5 FILE...'

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

CALL WriteAdditionalElemData( FileName,ElementOut)
CALL WriteAdditionalFieldData(FileName,FieldOut)

IF(MPIRoot) CALL MarkWriteSuccessfull(FileName)
GETTIME(EndT)
CALL DisplayMessageAndTime(EndT-StartT, 'DONE', DisplayDespiteLB=.TRUE., DisplayLine=.FALSE.)

#if USE_MPI
! Since we are going to abort directly after this wenn an error state is written, make sure that all processors are finished
! with everything or we might end up with a non-valid error state file
IF (isErrorFile) CALL MPI_BARRIER(MPI_COMM_FLEXI,iError)
#endif
END SUBROUTINE WriteState

END MODULE MOD_HDF5_Output_State
