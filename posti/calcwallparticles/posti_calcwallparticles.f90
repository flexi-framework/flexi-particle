!=================================================================================================================================
! Copyright (c) 2016  Prof. Claus-Dieter Munz 
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
!> Tool used to postprocess the ErosionSurfState files generated by the erosion tracking in FLEXI
!> SurfState files only contain values on the surfMesh
!> General process is as follows:
!>   * Read in parameter file (used to recreate the conditions during the simulation)
!>   * Read in of mesh (global, only single execution)
!>   * For each vsurfMesh face and particle species
!>       * Calculate integral values of impact angle "Alpha" and kinetic energy "Ekin"
!===================================================================================================================================
PROGRAM wallparticles
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Commandline_Arguments
USE MOD_Analyze_Vars
USE MOD_AnalyzeEquation_Vars
USE MOD_Restart_Vars
USE MOD_HDF5_Input
USE MOD_ReadInTools,                ONLY:GETLOGICAL,GETREAL,GETREALARRAY
USE MOD_Restart,                    ONLY:DefineParametersRestart,InitRestart,FinalizeRestart
USE MOD_Interpolation,              ONLY:DefineParametersInterpolation,InitInterpolation,FinalizeInterpolation
USE MOD_Mesh,                       ONLY:DefineParametersMesh,InitMesh,FinalizeMesh
USE MOD_Mesh_Vars,                  ONLY:MeshFile
USE MOD_IO_HDF5                 
USE MOD_Output,                     ONLY:DefineParametersOutput,InitOutput,FinalizeOutput
USE MOD_Analyze,                    ONLY:DefineParametersAnalyze,FinalizeAnalyze
USE MOD_MPI,                        ONLY:DefineParametersMPI,InitMPI
#if USE_MPI
USE MOD_MPI,                        ONLY:InitMPIvars,FinalizeMPI
#endif /*MPI*/ 
#if USE_PARTICLES
USE MOD_Particle_Analyze,           ONLY:DefineParametersParticleAnalyze,InitParticleAnalyze,FinalizeParticleAnalyze
USE MOD_Particle_Boundary_Vars,     ONLY:nSurfSample,PartBound,nPartBound,SampWall,surfMesh,LowVeloRemove
USE MOD_Particle_Boundary_Sampling, ONLY:InitParticleBoundarySampling
USE MOD_Particle_Erosion,           ONLY:DefineParametersParticleErosion,InitParticleErosion,FinalizeParticleErosion
USE MOD_Particle_Erosion_Analyze,   ONLY:CalcSurfaceValues
USE MOD_Particle_Erosion_Vars,      ONLY:nErosionVars
USE MOD_ErosionPoints,              ONLY:DefineParametersErosionPoints,InitErosionPoints,FinalizeErosionPoints
USE MOD_ErosionPoints_Vars
USE MOD_Particle_Surfaces,          ONLY:InitParticleSurfaces
USE MOD_Particle_Mesh
USE MOD_Particle_Boundary_Sampling, ONLY:FinalizeParticleBoundarySampling,RestartParticleBoundarySampling
!USE MOD_Particle_Tracking_Vars,     ONLY:DoRefMapping
USE MOD_CalcWallParticles
USE MOD_CalcWallParticles_Analyze,  ONLY:CalcWallSurfaceValues,AnalyzeEquation
USE MOD_ParticleInit,               ONLY:InitParticles,DefineParametersParticles,FinalizeParticles
USE MOD_PICInit,                    ONLY:DefineParametersPIC
USE MOD_Particle_Vars,              ONLY:nSpecies,ManualTimeStep
USE MOD_CalcWallParticles_Restart
USE MOD_CalcWallParticles_SurfAvg
USE MOD_CalcWallParticles_Vars
USE MOD_Particle_Restart
USE MOD_CalcWallParticles_Analyze,  ONLY:InitAnalyze
#if USE_MPI
USE MOD_Particle_MPI,               ONLY:InitParticleMPI
#endif /*MPI*/ 
#endif /*PARTICLES*/
USE MOD_Indicator,                  ONLY:DefineParametersIndicator,InitIndicator,FinalizeIndicator
USE MOD_ReadInTools
USE MOD_Restart_Vars,               ONLY:RestartFile
USE MOD_StringTools,                ONLY:STRICMP, GetFileExtension
USE MOD_Posti_CalcWallParticles_Vars
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                    :: Time                                                                   !< Used to measure simulation time
REAL                    :: ManualTimeStep_opt                                                     !< Pass dt to main code
INTEGER                 :: i,iBound,iVal,iSide,p,q
INTEGER                 :: boundaryNum
LOGICAL                 :: ErosionDataExists
CHARACTER(LEN=255)      :: remap_opt_name,format_remap_opt
!===================================================================================================================================
CALL SetStackSizeUnlimited()
CALL InitMPI()
IF (nProcessors.GT.1) CALL CollectiveStop(__STAMP__, &
     'This tool is designed only for single execution!')

CALL ParseCommandlineArguments()
ParameterFile = Args(1)

! Define parameters needed
CALL DefineParametersMPI()
CALL DefineParametersIO_HDF5()
CALL DefineParametersInterpolation()
CALL DefineParametersRestart()
CALL DefineParametersOutput()
CALL DefineParametersMesh()
CALL DefineParametersIndicator()
CALL DefineParametersAnalyze()
! Particles
#if USE_PARTICLES
CALL DefineParametersParticles()
CALL DefineParametersParticleMesh()
CALL DefineParametersPIC()
CALL DefineParametersParticleAnalyze()
CALL DefineParametersParticleErosion()
CALL DefineParametersErosionPoints()

CALL prms%SetSection("CalcWallParticles")
CALL prms%CreateStringOption( "Part-PostiAnalyzeMethod",  "Method for integral calculation.")
CALL prms%CreateLogicalOption("Part-PostiCalcAvg",        "Flag if an averaged statistics should be written.")
CALL prms%CreateLogicalOption("Part-PostiSurfAvg",        "Flag if an averaged surfState should be written.")
CALL prms%CreateRealArrayOption("Part-PostiSurfAvgDir",   "Vector for averaging direction")
CALL prms%CreateLogicalOption("Part-PostiSurfRemap",      "Flag if an surfState should be recalculated from impact files.")
CALL prms%CreateRealOption(   "Part-PostiDtRemap",        "Time step used for erosion remapping.")
CALL prms%CreateIntOption(    "Part-PostiBoundaryNumber", "If passed, only matching boundary will be visualized.")
CALL prms%CreateIntOption(    "Part-PostiReflCount",      "If passed, only particles with matching reflections will be counted.")
#endif /*PARTICLES*/

! Parse parameters
! check for command line argument --help or --markdown
IF (doPrintHelp.GT.0) THEN
  CALL PrintDefaultParameterFile(doPrintHelp.EQ.2, Args(1))
  STOP
END IF
! check if parameter file is given
IF ((nArgs.LT.1).OR.(.NOT.(STRICMP(GetFileExtension(Args(1)),'ini')))) THEN
  CALL CollectiveStop(__STAMP__,'ERROR - Invalid syntax. Please use: calcwallparticles prm-file')
END IF
CALL prms%read_options(Args(1))


SWRITE(UNIT_stdOut,'(132("="))')
SWRITE(UNIT_stdOut,'(A)')
SWRITE(UNIT_stdOut,'(A)') &
".______      ___      .______     .___________. __    ______  __       _______     _______."
SWRITE(UNIT_stdOut,'(A)') &
"|   _  \    /   \     |   _  \    |           ||  |  /      ||  |     |   ____|   /       |"
SWRITE(UNIT_stdOut,'(A)') &
"|  |_)  |  /  ^  \    |  |_)  |   `---|  |----`|  | |  ,----'|  |     |  |__     |   (----`"
SWRITE(UNIT_stdOut,'(A)') &
"|   ___/  /  /_\  \   |      /        |  |     |  | |  |     |  |     |   __|     \   \    "
SWRITE(UNIT_stdOut,'(A)') &
"|  |     /  _____  \  |  |\  \----.   |  |     |  | |  `----.|  `----.|  |____.----)   |   "
SWRITE(UNIT_stdOut,'(A)') &
"| _|    /__/     \__\ | _| `._____|   |__|     |__|  \______||_______||_______|_______/    "
SWRITE(UNIT_stdOut,'(A)')
SWRITE(UNIT_stdOut,'(132("="))')                                                                                  
! Measure init duration
StartTime=FLEXITIME()

AnalyzeString = TRIM(GETSTR('Part-PostiAnalyzeMethod'   , ''))
postiAvg      = GETLOGICAL( 'Part-PostiCalcAvg'         , '.FALSE.')
surfAvg       = GETLOGICAL( 'Part-PostiSurfAvg'         , '.FALSE.')
surfRemap     = GETLOGICAL( 'Part-PostiSurfRemap'       , '.FALSE.')
! Set ManualTimeStep so FLEXI doesn't try to find one without having a flow field
IF (surfRemap) THEN
    dt_remap           = GETREAL( 'Part-PostiDtRemap'       , '1.E-8')
    ManualTimeStep     = dt_remap
    ManualTimeStep_opt = dt_remap
ELSE
! Set a dummy ManualTimeStep to make FLEXI happy
    ManualTimeStep     = 1.
    ManualTimeStep_opt = 1.
END IF
boundaryNum   = GETINT(     'Part-PostiBoundaryNumber'  , '-1')
surfReflCount = GETINT(     'Part-PostiReflCount'       , '-1')

! Initialization
CALL InitInterpolation()
#if FV_ENABLED
CALL InitFV_Basis()
#endif
CALL InitOutput()
#if USE_PARTICLES
CALL InitParticleErosion
#endif /*PARTICLES*/ 
CALL InitMesh(meshMode=2)
CALL InitRestart()
CALL InitIndicator()
#if USE_MPI
CALL InitMPIvars()
#endif /*MPI*/
#if USE_PARTICLES
#if USE_MPI
CALL InitParticleMPI
#endif /*MPI*/
CALL InitElemBoundingBox()
CALL InitParticleSurfaces
CALL InitParticles(ManualTimeStep_opt)
#endif /*PARTICLES*/ 
CALL InitAnalyze()
#if USE_PARTICLES
CALL InitErosionPoints()
#endif /*PARTICLES*/

#if USE_PARTICLES
! Check if we have a direction if averaging for nSurfSample > 1
IF (surfAvg) THEN
    surfAvgDir  = GETREALARRAY('Part-PostiSurfAvgDir',3)
    ! Didn't get a direction, abort
    IF (ALL(surfAvgDir.EQ.0)) THEN
        CALL Abort(&
      __STAMP__,&
      'Spatial averaging currently only implemented for nSurfSample = 1. or given direction in "Part-PostiSurfAvgDir"')
    END IF
ENDIF


IF(postiAvg) THEN
    DO i=2,nArgs
        RestartFile = Args(i)

        ! Check if we want to perform a restart
        IF (LEN_TRIM(RestartFile).GT.0) THEN
            SWRITE(UNIT_StdOut,'(A,A,A)',ADVANCE='NO')' | Reading file "',TRIM(RestartFile),'" ... '
            ! Set flag indicating a restart to other routines
            DoRestart = .TRUE.
            ! Read in parameters of restart solution
            CALL OpenDataFile(RestartFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
            CALL DatasetExists(File_ID,'RestartData',ErosionDataExists)

            IF (.NOT.ErosionDataExists) THEN
                SWRITE(UNIT_StdOut,'(A)')'Not an erosion surfState. Skipping!'
                CYCLE
            ELSE
                SWRITE(UNIT_StdOut,'(A)')'Done'
            END IF

            CALL ReadAttribute(File_ID,'Time',1,RealScalar=RestartTime)
            CALL CloseDataFile()
        END IF

        ! We are calling standard routines, so make sure they actually calculate something
        doCalcWallParticles = .TRUE.

        CALL RestartParticleBoundarySampling()
        CALL CalcWallSurfaceValues(restart_opt=.TRUE.)
        CALL AnalyzeEquation(RestartTime)
    END DO
END IF

IF(surfAvg) THEN
    DO i=2,nArgs
        RestartFile = Args(i)

        ! Check if we want to perform a restart
        IF (LEN_TRIM(RestartFile).GT.0) THEN
            SWRITE(UNIT_StdOut,'(A,A,A)',ADVANCE='NO')' | Reading file "',TRIM(RestartFile),'" ... '
            ! Set flag indicating a restart to other routines
            DoRestart = .TRUE.
            ! Read in parameters of restart solution
            CALL OpenDataFile(RestartFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
            CALL DatasetExists(File_ID,'RestartData',ErosionDataExists)

            IF (.NOT.ErosionDataExists) THEN
                SWRITE(UNIT_StdOut,'(A)')'Not an erosion surfState. Skipping!'
                CYCLE
            ELSE
                SWRITE(UNIT_StdOut,'(A)')'Done'
            END IF

            CALL ReadAttribute(File_ID,'Time',1,RealScalar=RestartTime)
            CALL CloseDataFile()
        END IF

        ! We are calling standard routines, so make sure they actually calculate something
        doCalcWallParticles = .TRUE.
        
        ! We need this to have all arrays available
        CALL RestartParticleBoundarySampling(remap_opt=Args(i))
        CALL CalcWallSurfaceValues(restart_opt=.TRUE.)
    
        SWRITE(UNIT_StdOut,'(A,A,A)')' | Starting spatial averaging of file "',TRIM(RestartFile),'"'
        CALL InitParticleGeometry()
        CALL InitCalcWallParticles_SurfAvg()
        CALL CalcWallParticles_SurfAvg()
        CALL WriteAvgSampleToHDF5(TRIM(MeshFile),RestartTime)
    END DO
END IF

IF(surfRemap) THEN
    ! Delete old values
    DO iSide=1,SurfMesh%nSides
        IF (nSpecies.EQ.1) THEN
            DO p=1,nSurfSample
                DO q=1,nSurfSample
                    DO iVal=1,nErosionVars
                        SampWall(iSide)%State(iVal,p,q) = 0.
                    END DO !iVal
                END DO !q
            END DO !p
        ELSE
            DO p=1,nSurfSample
                DO q=1,nSurfSample
                    DO iVal=1,(nErosionVars*(nSpecies+1))
                        SampWall(iSide)%State(iVal,p,q) = 0.
                    END DO !iVal
                END DO !q
            END DO !p
        END IF !nSpecies
    END DO
    
    WRITE(UNIT_StdOut,'(132("-"))')
    WRITE(UNIT_StdOut,'(A)') ' START SurfData remapping'
    WRITE(UNIT_StdOut,'(132("-"))')
    
    ! Added to prevent log spam as we are only interested in the first impacts here
    LowVeloRemove = .FALSE.
    
    DO i=2,nArgs
        RestartFile = Args(i)
        
!        IF (.NOT.DoRefMapping) THEN
!            CALL Abort(&
!          __STAMP__,&
!          'SurfMesh remapping currently only implemented for DoRefMapping=T.')
!        END IF
        
        ! Check if we want to perform a restart
        IF (LEN_TRIM(RestartFile).GT.0) THEN
            ! Set flag indicating a restart to other routines
            DoRestart = .TRUE.
            ! Read in parameters of restart solution
            CALL OpenDataFile(RestartFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
            CALL ReadAttribute(File_ID,'Time',1,RealScalar=RestartTime)
            CALL CloseDataFile()
        END IF
        
        ! Change wall model to avoid unnecessary dependencies
        DO iBound=1,nPartBound
            IF(PartBound%TargetBoundCond(iBound).EQ.PartBound%ReflectiveBC) THEN
                PartBound%WallModel(iBound) = 'perfRef'
            END IF
        END DO
               
!        SWRITE(UNIT_StdOut,'(A,A)')' | Starting remapping surface values of file "',TRIM(RestartFile)
        SWRITE(UNIT_StdOut,'(A,I3,A,I3)')' | Remapping surface values of file ',i-1,' of ',nArgs-1
    
        ! Restart particles
        IF (boundaryNum .NE. -1) THEN
            ! Respect reflection counter
            IF (surfReflCount .NE. -1) THEN
                CALL CalcWallParticlesRestart(boundary_opt = boundaryNum, reflCount_opt=surfReflCount)
                ! We are calling standard routines, so make sure they actually calculate something
                doCalcWallParticles = .TRUE.
                ! Write the recalculated statistics
                CALL CalcWallSurfaceValues(restart_opt=.TRUE.)
                CALL AnalyzeEquation(RestartTime)
            ELSE
                CALL CalcWallParticlesRestart(boundary_opt = boundaryNum)
            END IF
        ELSE
            ! Respect reflection counter
            IF (surfReflCount .NE. -1) THEN
                CALL CalcWallParticlesRestart(reflCount_opt=surfReflCount)
                ! We are calling standard routines, so make sure they actually calculate something
                doCalcWallParticles = .TRUE.
                ! Write the recalculated statistics
                CALL CalcWallSurfaceValues(restart_opt=.TRUE.)
                CALL AnalyzeEquation(RestartTime)
            ELSE
                CALL CalcWallParticlesRestart()
            END IF
        END IF
    END DO
    ! Write new solution
    IF (surfReflCount .NE. -1) THEN
            ! Cast integer to string
            IF (surfReflCount<10) THEN
                format_remap_opt = "(A23,I1)"
            ELSE
                format_remap_opt = "(A23,I2)"
            END IF
            
            WRITE(remap_opt_name,format_remap_opt) '_ErosionRemapState_refl',surfReflCount
            
            CALL CalcSurfaceValues(restart_opt=.TRUE.,remap_opt=remap_opt_name)
    ELSE
        CALL CalcSurfaceValues(restart_opt=.TRUE.,remap_opt='_ErosionRemapState')
    END IF
END IF

#endif /*PARTICLES*/


! Finalize
CALL FinalizeCalcWallParticles_SurfAvg
CALL FinalizeOutput()
CALL FinalizeAnalyze()
#if USE_PARTICLES
CALL FinalizeParticleAnalyze
CALL FinalizeParticleErosion
CALL FinalizeErosionPoints
CALL FinalizeParticles
CALL FinalizeParticleBoundarySampling
#endif /*PARTICLES*/ 
CALL FinalizeInterpolation()
CALL FinalizeMesh()
#if FV_ENABLED
CALL FinalizeFV_Basis()
#endif
CALL FinalizeIndicator()
! Measure simulation duration
Time=FLEXITIME()
CALL FinalizeParameters()
CALL FinalizeCommandlineArguments()
#if USE_MPI
CALL MPI_FINALIZE(iError)
IF(iError .NE. 0) STOP 'MPI finalize error'
CALL FinalizeMPI()
#endif /*MPI*/ 
SWRITE(UNIT_stdOut,'(132("="))')
SWRITE(UNIT_stdOut,'(A,F8.2,A)') ' CALCWALLPARTICLES FINISHED! [',Time-StartTime,' sec ]'
SWRITE(UNIT_stdOut,'(132("="))')

END PROGRAM wallparticles