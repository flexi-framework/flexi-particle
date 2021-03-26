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
#include "eos.h"

#if FV_ENABLED
#error "This testcase is not tested with FV"
#endif

!==================================================================================================================================
!> The channel case is a setup according to the Moser channel
!==================================================================================================================================
MODULE MOD_Testcase
! MODULES
USE MOD_Testcase_Vars
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES

INTERFACE DefineParametersTestcase
  MODULE PROCEDURE DefineParametersTestcase
END INTERFACE

INTERFACE InitTestcase
  MODULE PROCEDURE InitTestcase
END INTERFACE

INTERFACE FinalizeTestcase
  MODULE PROCEDURE FinalizeTestcase
END INTERFACE

INTERFACE ExactFuncTestcase
  MODULE PROCEDURE ExactFuncTestcase
END INTERFACE

INTERFACE CalcForcing
  MODULE PROCEDURE CalcForcing
END INTERFACE

INTERFACE TestcaseSource
  MODULE PROCEDURE TestcaseSource
END INTERFACE

INTERFACE AnalyzeTestCase
  MODULE PROCEDURE AnalyzeTestCase
END INTERFACE

INTERFACE GetBoundaryFluxTestcase
  MODULE PROCEDURE GetBoundaryFluxTestcase
END INTERFACE

INTERFACE GetBoundaryFVgradientTestcase
  MODULE PROCEDURE GetBoundaryFVgradientTestcase
END INTERFACE

INTERFACE Lifting_GetBoundaryFluxTestcase
  MODULE PROCEDURE Lifting_GetBoundaryFluxTestcase
END INTERFACE

PUBLIC:: DefineParametersTestcase
PUBLIC:: InitTestcase
PUBLIC:: FinalizeTestcase
PUBLIC:: ExactFuncTestcase
PUBLIC:: TestcaseSource
PUBLIC:: CalcForcing
PUBLIC:: AnalyzeTestCase
PUBLIC:: GetBoundaryFluxTestcase
PUBLIC:: GetBoundaryFVgradientTestcase
PUBLIC:: Lifting_GetBoundaryFluxTestcase

CONTAINS

!==================================================================================================================================
!> Define parameters
!==================================================================================================================================
SUBROUTINE DefineParametersTestcase()
! MODULES
USE MOD_Globals
USE MOD_ReadInTools ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection("Testcase")
CALL prms%CreateRealOption('ChannelMach', "Bulk mach number used in the channel testcase.", '0.1')
CALL prms%CreateIntOption('nWriteStats', "Write testcase statistics to file at every n-th AnalyzeTestcase step.", '100')
CALL prms%CreateIntOption('nAnalyzeTestCase', "Call testcase specific analysis routines every n-th timestep. "//&
                                              "(Note: always called at global analyze level)", '1000')
CALL prms%CreateLogicalOption(  'Part-CustomChannel', "Allow channel dimensions other than Moser")
CALL prms%CreateRealOption(     'Part-ChannelReTau',  "Custom channel Re_tau")
CALL prms%CreateRealOption(     'Part-ChannelUTau',   "Custom channel U_tau")
CALL prms%CreateRealOption(     'Part-ChannelUBulk',  "Custom channel bulk velocity")
CALL prms%CreateRealOption(     'Part-ChannelDelta',  "Custom channel half height")
END SUBROUTINE DefineParametersTestcase

!==================================================================================================================================
!> Specifies all the initial conditions. The state in conservative variables is returned.
!==================================================================================================================================
SUBROUTINE InitTestcase()
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_ReadInTools,        ONLY: GETINT,GETREAL,GETLOGICAL
USE MOD_Output_Vars,        ONLY: ProjectName
USE MOD_Equation_Vars,      ONLY: RefStatePrim,IniRefState,RefStateCons
USE MOD_EOS,                ONLY: PrimToCons
USE MOD_EOS_Vars,           ONLY: kappa,mu0,R
USE MOD_Output,             ONLY: InitOutputToFile
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                     :: c1
REAL                     :: bulkMach,pressure
CHARACTER(LEN=7)         :: varnames(2)
REAL                     :: UE(PP_2Var)
!==================================================================================================================================
SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT TESTCASE CHANNEL...'

#if FV_ENABLED
CALL CollectiveStop(__STAMP__, &
  'The testcase has not been implemented for FV yet!')
#endif

nWriteStats      = GETINT('nWriteStats','100')
nAnalyzeTestCase = GETINT( 'nAnalyzeTestCase','1000')
customChannel    = GETLOGICAL('Part-CustomChannel','.FALSE.')

! Channel dimensions and BCs other than Moser
IF (customChannel) THEN
  uBulk       = GETREAL('Part-ChannelUBulk','0.')
  uTau        = GETREAL('Part-ChannelUtau', '0.')
!  uBulkScale  = 1./uBulk
  Re_tau      = GETREAL('Part-ChannelReTau','0.')
  SWRITE(Unit_STDOUT,'(A)') ' | Warning: Channel Init based on Moser. Initial state might be inaccurate!'
! Non-dimensional case with given Re_tau according to Moser
ELSE
  uBulkScale  = 1.
  Re_tau      = 1/mu0
  c1          = 2.4390244
  uBulk       = c1 * ((Re_tau+c1)*LOG(Re_tau+c1) + 1.3064019*(Re_tau + 29.627395*EXP(-1./11.*Re_tau) + 0.66762137*(Re_tau+3) &
              * EXP(-Re_tau/3.))) - 97.4857927165
  uBulk       = uBulk/Re_tau
ENDIF

! Set the background pressure according to chosen bulk Mach number
bulkMach = GETREAL('ChannelMach','0.1')
pressure = (uBulk/bulkMach)**2*RefStatePrim(DENS,IniRefState)/kappa
RefStatePrim(PRES,IniRefState) = pressure
! TODO: ATTENTION only sRho and Pressure of UE filled!!!
UE(EXT_SRHO) = 1./RefStatePrim(DENS,IniRefState)
UE(EXT_PRES) = RefStatePrim(PRES,IniRefState)
RefStatePrim(TEMP,IniRefState) = TEMPERATURE_HE(UE)
CALL PrimToCons(RefStatePrim(:,IniRefState),RefStateCons(:,IniRefState))

IF (customChannel) THEN
  rho      = RefStatePrim(DENS,IniRefState)
  delta    = GETREAL('Part-ChannelDelta','0.')
  uBulkScale  = 1./(uBulk*rho)

  ! Calculate new forcing pressure
  dpdx     = -(Re_tau**2.)*(mu0**2.)/(rho*delta**3.) !-(Re_tau**2)*(mu0**2)/rho

  ! Tell the user the calculated variables to check
  SWRITE(Unit_STDOUT,'(A,F6.2)')   ' | Bulk velocity given. uBulk =',uBulk
  SWRITE(Unit_STDOUT,'(A,F6.2,A)') ' | Associated pressure gradient. -dp/dx=:', dpdx, 'Pa s'
ELSE
  ! Re_tau^2*rho*nu^2/delta^3
  dpdx = -1.

  SWRITE(Unit_STDOUT,'(A,F6.2)')   ' | Bulk velocity based on initial velocity profile =',uBulk
  SWRITE(Unit_STDOUT,'(A,F6.2)')   ' | Associated pressure for Mach = 0.1 is', (uBulk/0.1)**2*RefStatePrim(1,IniRefState)/kappa
ENDIF

IF(.NOT.MPIRoot) RETURN

ALLOCATE(writeBuf(3,nWriteStats))
Filename = TRIM(ProjectName)//'_Stats'
varnames(1) = 'dpdx'
varnames(2) = 'bulkVel'
CALL InitOutputToFile(Filename,'Statistics',2,varnames)

SWRITE(UNIT_stdOut,'(A)')' INIT TESTCASE CHANNEL DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')
END SUBROUTINE InitTestcase



!==================================================================================================================================
!> Specifies all the initial conditions. The state in conservative variables is returned.
!==================================================================================================================================
SUBROUTINE ExactFuncTestcase(tIn,x,Resu,Resu_t,Resu_tt)
! MODULES
USE MOD_Preproc,      ONLY: PP_Pi
USE MOD_Globals,      ONLY: Abort
USE MOD_Equation_Vars,ONLY: RefStatePrim,IniRefState
USE MOD_EOS,          ONLY: PrimToCons
USE MOD_EOS_Vars,     ONLY: mu0
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
REAL,INTENT(IN)                 :: x(3),tIn
REAL,INTENT(OUT)                :: Resu(PP_nVar),Resu_t(PP_nVar),Resu_tt(PP_nVar)
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                            :: yplus,prim(PP_nVarPrim),amplitude
REAL                            :: x_int(3)
!==================================================================================================================================
!Channel Testcase: set mu0 = 1/Re_tau, rho=1, pressure adapted, Mach=0.1 according to Moser!!
!and hence: u_tau=tau=-dp/dx=1, and t=t+=u_tau*t/delta
Prim(:) = RefStatePrim(:,IniRefState) ! prim=(/1.,0.3,0.,0.,0.71428571/)
IF (customChannel) THEN
  IF(x(2).LE.0) THEN
      yPlus = (x(2)+delta)*(rho*utau/mu0)
  ELSE
      yPlus = (delta-x(2))*(rho*utau/mu0)
  END IF
ELSE
  IF(x(2).LE.0) THEN
    yPlus = (x(2)+1.)*Re_tau ! Re_tau=590
  ELSE
    yPlus = (1.-x(2))*Re_tau ! Re_tau=590
  END IF
ENDIF
!Prim(2)=uPlus
Prim(VEL1) = uBulkScale*(1./0.41*log(1+0.41*yPlus)+7.8*(1-exp(-yPlus/11.)-yPlus/11.*exp(-yPlus/3.)))
!Prim(5)=(uBulk*sqrt(kappa*Prim(5)/Prim(1)))**2*Prim(1)/kappa ! Pressure such that Ma=1/sqrt(kappa*p/rho)
Amplitude = 0.1*Prim(VEL1)

#if EQNSYSNR == 2
IF (customChannel) THEN
  x_int(1) = x(1)/delta
  x_int(2) = x(2)/delta
  x_int(3) = x(3)/delta

  Prim(VEL1)=Prim(VEL1)+sin(20.0*PP_PI*(x_int(2)/(2.0)))*sin(20.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(30.0*PP_PI*(x_int(2)/(2.0)))*sin(30.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(35.0*PP_PI*(x_int(2)/(2.0)))*sin(35.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(40.0*PP_PI*(x_int(2)/(2.0)))*sin(40.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(45.0*PP_PI*(x_int(2)/(2.0)))*sin(45.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(50.0*PP_PI*(x_int(2)/(2.0)))*sin(50.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude

  Prim(VEL2)=Prim(VEL2)+sin(30.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(30.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL2)=Prim(VEL2)+sin(35.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(35.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL2)=Prim(VEL2)+sin(40.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(40.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL2)=Prim(VEL2)+sin(45.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(45.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude
  Prim(VEL2)=Prim(VEL2)+sin(50.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(50.0*PP_PI*(x_int(3)/(2*PP_PI)))*Amplitude

  Prim(VEL3)=Prim(VEL3)+sin(30.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(30.0*PP_PI*(x_int(2)/(2.0)))*Amplitude
  Prim(VEL3)=Prim(VEL3)+sin(35.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(35.0*PP_PI*(x_int(2)/(2.0)))*Amplitude
  Prim(VEL3)=Prim(VEL3)+sin(40.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(40.0*PP_PI*(x_int(2)/(2.0)))*Amplitude
  Prim(VEL3)=Prim(VEL3)+sin(45.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(45.0*PP_PI*(x_int(2)/(2.0)))*Amplitude
  Prim(VEL3)=Prim(VEL3)+sin(50.0*PP_PI*(x_int(1)/(4*PP_PI)))*sin(50.0*PP_PI*(x_int(2)/(2.0)))*Amplitude
ELSE
  Prim(VEL1)=Prim(VEL1)+sin(20.0*PP_PI*(x(2)/(2.0)))*sin(20.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(30.0*PP_PI*(x(2)/(2.0)))*sin(30.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(35.0*PP_PI*(x(2)/(2.0)))*sin(35.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(40.0*PP_PI*(x(2)/(2.0)))*sin(40.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(45.0*PP_PI*(x(2)/(2.0)))*sin(45.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL1)=Prim(VEL1)+sin(50.0*PP_PI*(x(2)/(2.0)))*sin(50.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude

  Prim(VEL2)=Prim(VEL2)+sin(30.0*PP_PI*(x(1)/(4*PP_PI)))*sin(30.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL2)=Prim(VEL2)+sin(35.0*PP_PI*(x(1)/(4*PP_PI)))*sin(35.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL2)=Prim(VEL2)+sin(40.0*PP_PI*(x(1)/(4*PP_PI)))*sin(40.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL2)=Prim(VEL2)+sin(45.0*PP_PI*(x(1)/(4*PP_PI)))*sin(45.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude
  Prim(VEL2)=Prim(VEL2)+sin(50.0*PP_PI*(x(1)/(4*PP_PI)))*sin(50.0*PP_PI*(x(3)/(2*PP_PI)))*Amplitude

  Prim(VEL3)=Prim(VEL3)+sin(30.0*PP_PI*(x(1)/(4*PP_PI)))*sin(30.0*PP_PI*(x(2)/(2.0)))*Amplitude
  Prim(VEL3)=Prim(VEL3)+sin(35.0*PP_PI*(x(1)/(4*PP_PI)))*sin(35.0*PP_PI*(x(2)/(2.0)))*Amplitude
  Prim(VEL3)=Prim(VEL3)+sin(40.0*PP_PI*(x(1)/(4*PP_PI)))*sin(40.0*PP_PI*(x(2)/(2.0)))*Amplitude
  Prim(VEL3)=Prim(VEL3)+sin(45.0*PP_PI*(x(1)/(4*PP_PI)))*sin(45.0*PP_PI*(x(2)/(2.0)))*Amplitude
  Prim(VEL3)=Prim(VEL3)+sin(50.0*PP_PI*(x(1)/(4*PP_PI)))*sin(50.0*PP_PI*(x(2)/(2.0)))*Amplitude
ENDIF
#endif

Prim(TEMP) = 0. ! T does not matter for prim to cons
CALL PrimToCons(prim,Resu)

Resu_t =0.
Resu_tt=0.

END SUBROUTINE ExactFuncTestcase



!==================================================================================================================================
!> Compute bulk velocity for forcing term of the channel.
!==================================================================================================================================
SUBROUTINE CalcForcing(t,dt)
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_DG_Vars,        ONLY: U
USE MOD_Mesh_Vars,      ONLY: sJ
USE MOD_Analyze_Vars,   ONLY: wGPVol,Vol
USE MOD_Mesh_Vars,      ONLY: nElems
#if USE_MPI
USE MOD_MPI_Vars
#endif
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
REAL,INTENT(IN)                 :: t,dt
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: i,j,k,iElem
!==================================================================================================================================
BulkVel =0.
DO iElem=1,nElems
  DO k=0,PP_NZ; DO j=0,PP_N; DO i=0,PP_N
    BulkVel = BulkVel+U(MOM1,i,j,k,iElem)/U(DENS,i,j,k,iElem)*wGPVol(i,j,k)/sJ(i,j,k,iElem,0)
  END DO; END DO; END DO
END DO

#if USE_MPI
CALL MPI_ALLREDUCE(MPI_IN_PLACE,BulkVel,1,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_FLEXI,iError)
#endif
BulkVel = BulkVel/Vol
END SUBROUTINE CalcForcing


!==================================================================================================================================
!> Apply forcing term equivalent to a constant streamwise pressure gradient
!==================================================================================================================================
SUBROUTINE TestcaseSource(Ut)
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Mesh_Vars, ONLY:sJ,nElems
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
REAL,INTENT(INOUT)              :: Ut(CONS,0:PP_N,0:PP_N,0:PP_NZ,1:nElems) !< solution time derivative
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: i,j,k,iElem
!==================================================================================================================================
! Apply forcing with the pressure gradient
DO iElem=1,nElems
  DO k=0,PP_NZ; DO j=0,PP_N; DO i=0,PP_N
    Ut(MOM1,i,j,k,iElem)=Ut(MOM1,i,j,k,iElem) -dpdx/sJ(i,j,k,iElem,0)
    Ut(ENER,i,j,k,iElem)=Ut(ENER,i,j,k,iElem) -dpdx*BulkVel/sJ(i,j,k,iElem,0)
  END DO; END DO; END DO
END DO
END SUBROUTINE TestcaseSource

!==================================================================================================================================
!> Output testcase statistics
!==================================================================================================================================
SUBROUTINE WriteStats()
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Output,       ONLY:OutputToFile
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!==================================================================================================================================
CALL OutputToFile(FileName,writeBuf(1,1:ioCounter),(/2,ioCounter/),RESHAPE(writeBuf(2:3,1:ioCounter),(/2*ioCounter/)))
ioCounter=0
END SUBROUTINE WriteStats

!==================================================================================================================================
!> Specifies periodic hill testcase
!==================================================================================================================================
SUBROUTINE AnalyzeTestcase(Time)
! MODULES
USE MOD_Globals
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
REAL,INTENT(IN)                 :: Time                   !< simulation time
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!==================================================================================================================================
IF(MPIRoot)THEN
  ioCounter=ioCounter+1
  writeBuf(:,ioCounter) = (/Time, dpdx, BulkVel/)
  IF(ioCounter.GE.nWriteStats) CALL WriteStats()
END IF
END SUBROUTINE AnalyzeTestCase

!==================================================================================================================================
!> Specifies all the initial conditions. The state in conservative variables is returned.
!==================================================================================================================================
SUBROUTINE FinalizeTestcase()
! MODULES
USE MOD_Globals
IMPLICIT NONE
!==================================================================================================================================
IF(MPIRoot.AND.ALLOCATED(writeBuf))THEN; CALL WriteStats(); DEALLOCATE(writeBuf); END IF
END SUBROUTINE



SUBROUTINE GetBoundaryFluxTestcase(SideID,t,Nloc,Flux,UPrim_master,                   &
#if PARABOLIC
                           gradUx_master,gradUy_master,gradUz_master,&
#endif
                           NormVec,TangVec1,TangVec2,Face_xGP)
! MODULES
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN)   :: SideID  !< ID of current side
REAL,INTENT(IN)      :: t       !< current time (provided by time integration scheme)
INTEGER,INTENT(IN)   :: Nloc    !< polynomial degree
REAL,INTENT(IN)      :: UPrim_master( PP_nVarPrim,0:Nloc,0:ZDIM(Nloc))    !< inner surface solution
#if PARABOLIC
REAL,INTENT(IN)      :: gradUx_master(PP_nVarLifting,0:Nloc,0:ZDIM(Nloc)) !> inner surface solution gradients in x-direction
REAL,INTENT(IN)      :: gradUy_master(PP_nVarLifting,0:Nloc,0:ZDIM(Nloc)) !> inner surface solution gradients in y-direction
REAL,INTENT(IN)      :: gradUz_master(PP_nVarLifting,0:Nloc,0:ZDIM(Nloc)) !> inner surface solution gradients in z-direction
#endif /*PARABOLIC*/
REAL,INTENT(IN)      :: NormVec (  3,0:Nloc,0:ZDIM(Nloc))  !< normal vectors on surfaces
REAL,INTENT(IN)      :: TangVec1(  3,0:Nloc,0:ZDIM(Nloc))  !< tangential1 vectors on surfaces
REAL,INTENT(IN)      :: TangVec2(  3,0:Nloc,0:ZDIM(Nloc))  !< tangential2 vectors on surfaces
REAL,INTENT(IN)      :: Face_xGP(  3,0:Nloc,0:ZDIM(Nloc))  !< positions of surface flux points
REAL,INTENT(OUT)     :: Flux(PP_nVar,0:Nloc,0:ZDIM(Nloc))  !< resulting boundary fluxes
!==================================================================================================================================
END SUBROUTINE GetBoundaryFluxTestcase


SUBROUTINE GetBoundaryFVgradientTestcase(SideID,t,gradU,UPrim_master)
USE MOD_PreProc
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN) :: SideID                                   !< ID of current side
REAL,INTENT(IN)    :: t                                        !< current time (provided by time integration scheme)
REAL,INTENT(IN)    :: UPrim_master(PP_nVarPrim,0:PP_N,0:PP_NZ) !< primitive solution from the inside
REAL,INTENT(OUT)   :: gradU       (PP_nVarPrim,0:PP_N,0:PP_NZ) !< FV boundary gradient
!==================================================================================================================================
END SUBROUTINE GetBoundaryFVgradientTestcase


SUBROUTINE Lifting_GetBoundaryFluxTestcase(SideID,t,UPrim_master,Flux)
USE MOD_PreProc
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN) :: SideID                                   !< ID of current side
REAL,INTENT(IN)    :: t                                        !< current time (provided by time integration scheme)
REAL,INTENT(IN)    :: UPrim_master(PP_nVarPrim,0:PP_N,0:PP_NZ) !< primitive solution from the inside
REAL,INTENT(OUT)   :: Flux(     PP_nVarLifting,0:PP_N,0:PP_NZ) !< lifting boundary flux
!==================================================================================================================================
END SUBROUTINE Lifting_GetBoundaryFluxTestcase

END MODULE MOD_Testcase
