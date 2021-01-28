!=================================================================================================================================
! Copyright (c) 2010-2020  Prof. Claus-Dieter Munz
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

!==================================================================================================================================
! Contains the routines that set up communicators and control non-blocking communication
!==================================================================================================================================
MODULE MOD_Particle_Init
! MODULES
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------

INTERFACE DefineParametersParticles
  MODULE PROCEDURE DefineParametersParticles
END INTERFACE

INTERFACE InitParticleGlobals
  MODULE PROCEDURE InitParticleGlobals
END INTERFACE InitParticleGlobals

INTERFACE InitParticles
  MODULE PROCEDURE InitParticles
END INTERFACE

INTERFACE FinalizeParticles
  MODULE PROCEDURE FinalizeParticles
END INTERFACE

INTERFACE PortabilityGetPID
  FUNCTION GetPID_C() BIND (C, name='getpid')
    !GETPID() is an intrinstic compiler function in gnu. This routine ensures the portability with other compilers.
    USE ISO_C_BINDING,         ONLY: PID_T => C_INT
    IMPLICIT NONE
    INTEGER(KIND=PID_T)        :: GetPID_C
  END FUNCTION GetPID_C
END INTERFACE

PUBLIC :: DefineParametersParticles
PUBLIC :: InitParticleGlobals
PUBLIC :: InitParticles
PUBLIC :: FinalizeParticles
!==================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Define parameters for particles
!==================================================================================================================================
SUBROUTINE DefineParametersParticles()
! MODULES
USE MOD_ReadInTools
USE MOD_ErosionPoints,              ONLY:DefineParametersErosionPoints
USE MOD_Particle_Analyze,           ONLY:DefineParametersParticleAnalyze,InitParticleAnalyze
USE MOD_Particle_Boundary_Sampling, ONLY:DefineParametersParticleBoundarySampling
USE Mod_Particle_Globals
USE MOD_Particle_Interpolation,     ONLY:DefineParametersParticleInterpolation
USE MOD_Particle_Mesh,              ONLY:DefineParametersParticleMesh
USE MOD_Particle_Vars
#if USE_MPI
USE MOD_LoadBalance,                ONLY:DefineParametersLoadBalance
USE MOD_Particle_MPI_Shared,        ONLY:DefineParametersMPIShared
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!==================================================================================================================================
CALL prms%SetSection('Tracking')

CALL prms%CreateIntFromStringOption('TrackingMethod', "Define Method that is used for tracking of particles:\n"                  //&
                                                      "refmapping   (1): reference mapping of particle position with (bi-)linear\n"//&
                                                      "                  and bezier (curved) description of sides.\n"            //&
                                                      "tracing      (2): tracing of particle path with (bi-)linear and bezier\n" //&
                                                      "                  (curved) description of sides.\n"                       //&
                                                      "triatracking (3): tracing of particle path with triangle-aproximation\n"  //&
                                                      "                  of (bi-)linear sides.\n",                                 &
                                                      "triatracking")
CALL addStrListEntry(               'TrackingMethod', 'refmapping'      ,REFMAPPING)
CALL addStrListEntry(               'TrackingMethod', 'tracing'         ,TRACING)
CALL addStrListEntry(               'TrackingMethod', 'triatracking'    ,TRIATRACKING)
CALL addStrListEntry(               'TrackingMethod', 'default'         ,TRIATRACKING)

CALL prms%CreateLogicalOption(      'TriaSurfaceFlux','Using Triangle-aproximation [T] or (bi-)linear and bezier (curved) '      //&
                                                      'description [F] of sides for surfaceflux.'                                  &
                                                    , '.TRUE.')

CALL prms%CreateLogicalOption(      'CountNbOfLostParts'      , 'Count number of lost particles during tracking that can not be '//&
                                                                'found with fallbacks.'                                            &
                                                              , '.FALSE.')

CALL prms%CreateIntOption(          'BezierClipLineVectorMethod',''                                                               &
                                                    , '2')
CALL prms%CreateIntOption(          'NbrOfRegions'  , 'Number of regions to be mapped to Elements'                                 &
                                                    , '0')
CALL prms%CreateIntOption(          'Part-nAuxBCs'  , 'Number of auxillary BCs that are checked during tracing'                    &
                                                    , '0')


CALL prms%CreateIntOption(          'Part-maxParticleNumber'   , 'Max number of particles in processor domain'                     &
                                                               , '1')
CALL prms%CreateIntOption(          'Part-NumberOfRandomSeeds' , 'Number of random seeds for particle random number generator'     &
                                                               , '0')
CALL prms%CreateIntOption(          'Part-RandomSeed[$]'       , 'Seed [$] for Random Number Generator'                            &
                                                               , '1'        , numberedmulti=.TRUE.)

! Timedisc
CALL prms%CreateLogicalOption(      'Part-SteadyState'         , 'Only update particle position while keeping fluid state frozen'  &
                                                               , '.FALSE.')
CALL prms%CreateRealOption(         'Part-ManualTimestep'      , 'Manual time step routine for frozen fluid state'                 &
                                                               , '0.')
CALL prms%CreateLogicalOption(      'Part-LowVeloRemove'       , 'Flag if low velocity particles should be removed'                &
                                                               , '.FALSE.')

CALL prms%CreateRealOption(         'Part-DelayTime'           , "During delay time the particles won't be moved so the fluid "  //&
                                                                 'field can be evolved'                                            &
                                                               , '0.')

CALL prms%CreateRealArrayOption(    'Part-Gravity'             , 'Gravitational acceleration as vector'                            &
                                                               , '0. , 0. , 0.')

#if CODE_ANALYZE
CALL prms%CreateIntOption(          'PartOut'                  , 'If compiled with CODE_ANALYZE flag: For This particle number'  //&
                                                                 ' every tracking information is written as STDOUT.'               &
                                                               , '0')
CALL prms%CreateIntOption(          'MPIRankOut'               , 'If compiled with CODE_ANALYZE flag: This MPI-Proc writes the'  //&
                                                                 ' tracking information for the defined PartOut.'
                                                               , '0')
#endif /*CODE_ANALYZE*/
CALL prms%CreateStringOption(       'Part-RecordType'          , 'Type of record plane.\n'                                       //&
                                                                 ' - plane\n'                                                      &
                                                               , 'none')
CALL prms%CreateLogicalOption(      'Part-RecordPart'          , 'Record particles at given record plane'  &
                                                               , '.FALSE.')
CALL prms%CreateIntOption(          'Part-RecordMemory'        , 'Record particles memory'  &
                                                               , '100')
CALL prms%CreateRealArrayOption(    'Part-RPThresholds'        , 'Record particles threshold'  &
                                                               , '0.,0.,0.,0.,0.,0.')
#if USE_RW
CALL prms%SetSection("Particle Random Walk")
!===================================================================================================================================
! >>> Values in this section only apply for turbulence models providing turbulent kinetic energy and a turbulent length/time scale
!===================================================================================================================================
CALL prms%CreateStringOption(       'Part-RWModel'  , 'Random walk model used for steady-state calculations.\n'                  //&
                                                      ' - Gosman\n'                                                              //&
                                                      ' - Dehbi\n'                                                               //&
                                                      ' - Langevin\n'                                                              &
                                                    , 'none')
CALL prms%CreateStringOption(       'Part-RWTime'   , 'Time stepping used for random walk model.\n'                              //&
                                                      ' - RK \n'                                                                 //&
                                                      ' - RW'                                                                      &
                                                    , 'RW')
#endif /* USE_RW */

!===================================================================================================================================
! >>> Options for particle SGS model
!===================================================================================================================================
CALL prms%CreateStringOption(       'Part-SGSModel' , 'SGS model used for reconstruction of SGS influence on particle\n'         //&
                                                      ' - Breuer \n'                                                             //&
                                                      ' - Breuer-Analytic \n'                                                    //&
                                                      ' - none'                                                                    &
                                                    , 'none')
CALL prms%CreateIntOption(          'Part-SGSNFilter','Number of cut-off modes in the high-pass SGS filter'                        &
                                                    , '2')

!===================================================================================================================================
! > Species
! >>> Values in this section appear multiple times
!===================================================================================================================================
CALL prms%SetSection("Particle Species")
! species inits and properties
CALL prms%CreateIntOption(          'Part-nSpecies'             , 'Number of species in part'                                      &
                                                                , '1')
CALL prms%CreateIntOption(          'Part-Species[$]-nInits'    , 'Number of different initial particle placements for Species [$]'&
                                                                , '0'        , numberedmulti=.TRUE.)
CALL prms%CreateIntFromStringOption('Part-Species[$]-RHSMethod' , 'Particle model used for forces calculation.\n'                //&
                                                                  ' - Wang\n'                                                    //&
                                                                  ' - Jacobs\n'                                                  //&
                                                                  ' - Vinkovic'                                                    &
                                                                , 'none'     , numberedmulti=.TRUE.)
CALL addStrListEntry(               'Part-Species[$]-RHSMethod' ,'none',            RHS_NONE)
CALL addStrListEntry(               'Part-Species[$]-RHSMethod' ,'tracer',          RHS_TRACER)
CALL addStrListEntry(               'Part-Species[$]-RHSMethod' ,'convergence',     RHS_CONVERGENCE)
CALL addStrListEntry(               'Part-Species[$]-RHSMethod' ,'Wang',            RHS_WANG)
CALL addStrListEntry(               'Part-Species[$]-RHSMethod' ,'Vinkovic',        RHS_VINKOVIC)
CALL addStrListEntry(               'Part-Species[$]-RHSMethod' ,'Jacobs',          RHS_JACOBS)
CALL addStrListEntry(               'Part-Species[$]-RHSMethod' ,'Jacobs-highRe',   RHS_JACOBSHIGHRE)
CALL prms%CreateRealOption(         'Part-Species[$]-MassIC'    , 'Particle mass of species [$] [kg]'                              &
                                                                , '0.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-DiameterIC', 'Particle diameter of species [$] [m]'                              &
                                                                , '0.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-DensityIC' , 'Particle density of species [$] [kg/m^3]'                       &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateStringOption(       'Part-Species[$]-velocityDistribution', 'Used velocity distribution.\n'                      //&
                                                                  ' - constant: all particles have the same velocity defined in' //&
                                                                  ' VeloVecIC\n'                                                 //&
                                                                  ' - fluid:    particles have local fluid velocity\n'             &
                                                                , 'constant', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-VeloIC'    , 'Absolute value of initial velocity. (ensemble velocity) '      &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-VeloVecIC ', 'Velocity vector for given species'                              &
                                                                , '0. , 0. , 0.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-VeloTurbIC', 'Turbulent fluctuation of initial velocity. (ensemble velocity) '&
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-LowVeloThreshold', 'Threshold velocity of particles after reflection.'      //&
                                                                  ' Slower particles are deleted [$] [m/s]'                        &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-HighVeloThreshold', 'Threshold velocity of particles in the entire field.'  //&
                                                                  ' Faster particles are deleted [$] [m/s]'                        &
                                                                , '0.'      , numberedmulti=.TRUE.)


! emission time
CALL prms%SetSection('Particle Species Emission')
CALL prms%CreateLogicalOption(      'Part-Species[$]-UseForEmission', 'Flag to use Init/Emission for emission'                     &
                                                                , '.FALSE.' , numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Species[$]-UseForInit', 'Flag to use Init/Emission for init'                             &
                                                                , '.TRUE.'  , numberedmulti=.TRUE.)
CALL prms%CreateIntOption(          'Part-Species[$]-initialParticleNumber', 'Initial particle number'                             &
                                                                , '0'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-InflowRiseTime', 'Time to ramp the number of inflow particles linearly from'//&
                                                                  ' zero to unity'                                                 &
                                                                , '0.'       , numberedmulti=.TRUE.)
CALL prms%CreateIntOption(          'Part-Species[$]-ParticleEmissionType', 'Define Emission Type for particles (volume'         //&
                                                                  ' emission)\n'                                                 //&
                                                                  '1 = emission rate in part/s,\n'//&
                                                                  '2 = emission rate part/iteration\n'&
                                                                , '2'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-ParticleEmission', 'Emission rate in part/s or part/iteration.'               &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-ParticleEmissionTime', 'Scale emission time for EmissionType==1.'             &
                                                                , '1.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-PartDensity', 'PartDensity (real particles per m^3) or (vpi_)cub./cyl.'     //&
                                                                   'as alternative to Part.Emis. in Type1 '                        &
                                                                 , '0.'     , numberedmulti=.TRUE.)

! emission region
CALL prms%CreateStringOption(       'Part-Species[$]-SpaceIC'   , 'Specifying Keyword for particle space condition of species '  //&
                                                                  '[$] in case of one init.\n'                                   //&
                                                                  ' - point\n'                                                   //&
                                                                  ' - line_with_equidistant_distribution\n'                      //&
                                                                  ' - line\n'                                                    //&
                                                                  ' - disc\n'                                                    //&
                                                                  ' - circle_equidistant\n'                                      //&
                                                                  ' - cuboid\n'                                                  //&
                                                                  ' - cylinder\n'                                                //&
                                                                  ' - Gaussian\n'                                                  &
                                                                , 'cuboid'  , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-BasePointIC','Base point for IC cuboid and IC sphere'                         &
                                                                 , '0. , 0. , 0.', numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-BaseVector1IC','First base vector for IC cuboid'                              &
                                                                 , '1. , 0. , 0.', numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-BaseVector2IC', 'Second base vector for IC cuboid'                            &
                                                                 , '0. , 1. , 0.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-BaseVariance','Variance for Gaussian distribtution'                           &
                                                                 ,'1.'           , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-NormalIC'   , 'Normal orientation of circle.'                                 &
                                                                 , '0. , 0. , 1.', numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Species[$]-CalcHeightFromDt', 'Calculated cuboid/cylinder height from v and dt'          &
                                                                , '.FALSE.'  , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-CuboidHeightIC'  , 'Height of cuboid if SpaceIC=cuboid'                       &
                                                                , '1.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-CylinderHeightIC', 'Third measure of cylinder  (set 0 for flat rectangle),' //&
                                                                  ' negative value = opposite direction'                           &
                                                                , '1.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-RadiusIC'  , 'Radius for IC circle'                                           &
                                                                , '1.'       , numberedmulti=.TRUE.)

! Exclude regions
CALL prms%CreateIntOption(          'Part-Species[$]-NumberOfExcludeRegions', 'Number of different regions to be excluded'         &
                                                                , '0'       , numberedmulti=.TRUE.)

CALL prms%SetSection("Particle Species nInits")
! if nInit > 0 some variables have to be defined twice
CALL prms%CreateIntFromStringOption('Part-Species[$]-Init[$]-RHSMethod' , 'Particle model used for forces calculation.\n'        //&
                                                                  ' - Wang\n'                                                    //&
                                                                  ' - Jacobs\n'                                                  //&
                                                                  ' - Vinkovic'                                                    &
                                                                , 'none'     , numberedmulti=.TRUE.)
CALL addStrListEntry(               'Part-Species[$]-Init[$]-RHSMethod' ,'none',            RHS_NONE)
CALL addStrListEntry(               'Part-Species[$]-Init[$]-RHSMethod' ,'tracer',          RHS_TRACER)
CALL addStrListEntry(               'Part-Species[$]-Init[$]-RHSMethod' ,'convergence',     RHS_CONVERGENCE)
CALL addStrListEntry(               'Part-Species[$]-Init[$]-RHSMethod' ,'Wang',            RHS_WANG)
CALL addStrListEntry(               'Part-Species[$]-Init[$]-RHSMethod' ,'Vinkovic',        RHS_VINKOVIC)
CALL addStrListEntry(               'Part-Species[$]-Init[$]-RHSMethod' ,'Jacobs',          RHS_JACOBS)
CALL addStrListEntry(               'Part-Species[$]-Init[$]-RHSMethod' ,'Jacobs-highRe',   RHS_JACOBSHIGHRE)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-MassIC'    , 'Particle mass of species [$] [kg]'                      &
                                                                , '0.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-DiameterIC', 'Particle diameter of species [$] [m]'                      &
                                                                , '0.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-DensityIC' , 'Particle density of species [$] [kg/m^3]'               &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateStringOption(       'Part-Species[$]-Init[$]-velocityDistribution', 'Used velocity distribution.\n'              //&
                                                                  ' - constant: all particles have the same velocity defined in' //&
                                                                  ' VeloVecIC\n'                                                 //&
                                                                  ' - fluid:    particles have local fluid velocity\n'             &
                                                                , 'constant', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-VeloIC'    , 'Absolute value of initial velocity. (ensemble velocity) ' &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-Init[$]-VeloVecIC ', 'Velocity vector for given species'                      &
                                                                , '0. , 0. , 0.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-VeloTurbIC', 'Turbulent fluctuation of initial velocity. (ensemble velocity) '&
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-LowVeloThreshold', 'Threshold velocity of particles after reflection.' //&
                                                                  ' Slower particles are deleted [$] [m/s]'                        &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-HighVeloThreshold', 'Threshold velocity of particles in the entire field.' //&
                                                                  ' Faster particles are deleted [$] [m/s]'                        &
                                                                , '0.'      , numberedmulti=.TRUE.)


! emission time
CALL prms%SetSection('Particle Species Ninits Emission')
CALL prms%CreateLogicalOption(      'Part-Species[$]-Init[$]-UseForEmission', 'Flag to use Init/Emission for emission'             &
                                                                , '.FALSE.' , numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Species[$]-Init[$]-UseForInit', 'Flag to use Init/Emission for init'                     &
                                                                , '.TRUE.'  , numberedmulti=.TRUE.)
CALL prms%CreateIntOption(          'Part-Species[$]-Init[$]-initialParticleNumber', 'Initial particle number'                     &
                                                                , '0'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-InflowRiseTime', 'Time to ramp the number of inflow particles linearly from' //&
                                                                  ' zero to unity'                                                 &
                                                                , '0.'       , numberedmulti=.TRUE.)
CALL prms%CreateIntOption(          'Part-Species[$]-Init[$]-ParticleEmissionType', 'Define Emission Type for particles (volume' //&
                                                                  ' emission)\n'                                                 //&
                                                                  '1 = emission rate in part/s,\n'//&
                                                                  '2 = emission rate part/iteration\n'&
                                                                , '2'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-ParticleEmission', 'Emission rate in part/s or part/iteration.'       &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-ParticleEmissionTime', 'Scale emission time for EmissionType==1.'     &
                                                                , '1.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-PartDensity', 'PartDensity (real particles per m^3) or (vpi_)cub./cyl.' //&
                                                                   'as alternative to Part.Emis. in Type1 '                        &
                                                                 , '0.'     , numberedmulti=.TRUE.)

! emission region
CALL prms%CreateStringOption(       'Part-Species[$]-Init[$]-SpaceIC'   , 'Specifying Keyword for particle space condition of species ' //&
                                                                  '[$] in case of one init.\n'                                   //&
                                                                  ' - point\n'                                                   //&
                                                                  ' - line_with_equidistant_distribution\n'                      //&
                                                                  ' - line\n'                                                    //&
                                                                  ' - Gaussian'                                                  //&
                                                                  ' - disc\n'                                                    //&
                                                                  ' - circle\n'                                                  //&
                                                                  ' - circle_equidistant\n'                                      //&
                                                                  ' - cuboid\n'                                                  //&
                                                                  ' - cylinder\n'                                                //&
                                                                  ' - sphere\n'                                                    &
                                                                , 'cuboid'  , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-Init[$]-BasePointIC','Base point for IC cuboid and IC sphere'                 &
                                                                 , '0. , 0. , 0.', numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-Init[$]-BaseVector1IC','First base vector for IC cuboid'                      &
                                                                 , '1. , 0. , 0.', numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-Init[$]-BaseVector2IC', 'Second base vector for IC cuboid'                    &
                                                                 , '0. , 1. , 0.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-BaseVariance','Variance for Gaussian distribtution'                   &
                                                                 ,'1.'           , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-Init[$]-NormalIC'   , 'Normal orientation of circle.'                         &
                                                                 , '0. , 0. , 1.', numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Species[$]-Init[$]-CalcHeightFromDt', 'Calculated cuboid/cylinder height from v and dt'  &
                                                                , '.FALSE.'  , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-CuboidHeightIC'  , 'Height of cuboid if SpaceIC=cuboid'               &
                                                                , '1.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-CylinderHeightIC', 'Third measure of cylinder  (set 0 for flat rectangle),' //&
                                                                  ' negative value = opposite direction'                           &
                                                                , '1.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-RadiusIC'  , 'Radius for IC circle'                                   &
                                                                , '1.'       , numberedmulti=.TRUE.)

! Exclude regions
CALL prms%CreateIntOption(          'Part-Species[$]-Init[$]-NumberOfExcludeRegions', 'Number of different regions to be excluded' &
                                                                , '0'       , numberedmulti=.TRUE.)

! Surface Flux
CALL prms%SetSection("Particle Surface Flux")
CALL prms%CreateIntOption(          'Part-Species[$]-nSurfacefluxBCs'  ,  'Number of SF emissions'                                 &
                                                                       , '0'       , numberedmulti=.TRUE.)
CALL prms%CreateIntOption(          'Part-Species[$]-Surfaceflux[$]-BC',  'PartBound to be emitted from'                           &
                                                                       , '0'       , numberedmulti=.TRUE.)
CALL prms%CreateStringOption(       'Part-Species[$]-Surfaceflux[$]-velocityDistribution', 'Specifying keyword for velocity distribution\n' //&
                                                                       ' - constant\n'                                           //&
                                                                       ' - fluid'                                                  &
                                                                       , 'constant', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Surfaceflux[$]-VeloIC', 'Velocity for inital Data'                            &
                                                                       , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Species[$]-Surfaceflux[$]-VeloIsNormal', 'VeloIC is in Surf-Normal instead of VeloVecIC' &
                                                                       , '.FALSE.' , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-Surfaceflux[$]-VeloVecIC','Normalized velocity vector'                        &
                                                                       , '0.0 , 0.0 , 0.0', numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Species[$]-Surfaceflux[$]-CircularInflow', 'Enables the utilization of a circular'     //&
                                                                         'region as a surface flux on the selected boundary. '   //&
                                                                         'Only possible on surfaces, which are in xy, xz, and '  //&
                                                                         'yz-planes.'                                              &
                                                                       , '.FALSE.' , numberedmulti=.TRUE.)
CALL prms%CreateIntOption(          'Part-Species[$]-Surfaceflux[$]-axialDir', 'Axial direction of coordinates in polar system'    &
                                                                                   , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Species[$]-Surfaceflux[$]-origin'  , 'Origin in orth(ogonal?) coordinates of polar system' &
                                                                      , '0.0 , 0.0', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Surfaceflux[$]-rmax', ' Max radius of to-be inserted particles'               &
                                                                      , '1E21'     , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Surfaceflux[$]-rmin', 'Min radius of to-be inserted particles'                &
                                                                      , '0.'       , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Surfaceflux[$]-PartDensity','PartDensity (real particles per m^3) or cub./' //&
                                                                        'cyl. as alternative  to Part.Emis. in Type1'              &
                                                                      , '0.'       , numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Species[$]-Surfaceflux[$]-ReduceNoise','Reduce stat. noise by global calc. of PartIns',  &
                                                                      '.FALSE.'    , numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Species[$]-Surfaceflux[$]-AcceptReject',' Perform ARM for skewness of RefMap-positioning'&
                                                                      , '.TRUE.'   , numberedmulti=.TRUE.)
CALL prms%CreateIntOption(          'Part-Species[$]-Surfaceflux[$]-ARM_DmaxSampleN', 'Number of sample intervals in xi/eta for '//&
                                                                        'Dmax-calc.'                                               &
                                                                      , '1'        , numberedmulti=.TRUE.)

CALL prms%CreateLogicalOption(      'OutputSurfaceFluxLinked'         , 'Flag to print the SurfaceFlux-linked Info'                &
                                                                      , '.FALSE.')
CALL prms%CreateLogicalOption(      'doPartIndex'                     , 'Flag to write out unique part index'                &
                                                                      , '.FALSE.')

!===================================================================================================================================
! > Boundaries
!===================================================================================================================================
CALL prms%SetSection("Particle Boundaries")
!CALL prms%CreateIntOption(          'Part-nBounds'              , 'Number of particle boundaries.'                                &
!                                                                , '1')
CALL prms%CreateStringOption(       'Part-Boundary[$]-Type'     , 'Used boundary condition for boundary.\n'                      //&
                                                                  '- open\n'                                                     //&
                                                                  '- reflective\n'                                               //&
                                                                  '- periodic\n'                                                   &
                                                                            , numberedmulti=.TRUE.)
CALL prms%CreateStringOption(       'Part-Boundary[$]-Name'     , 'Source Name of Boundary. Has to be same name as defined in'   //&
                                                                ' preproc tool'                                                    &
                                                                            , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-PeriodicVector[$]'    , 'Vector for periodic boundaries.'                              //&
                                                                  ' Has to be the same as defined in preproc.ini in their'       //&
                                                                  ' respective order. '                                            &
                                                                , '1.,0.,0.', numberedmulti=.TRUE.)

! Wall model =======================================================================================================================
CALL prms%SetSection("Particle Rebound Model")
CALL prms%CreateStringOption(       'Part-Boundary[$]-WallModel', 'Wall model to be used. Options:.\n'                           //&
                                                                  ' - perfRef  - perfect reflection\n'                           //&
                                                                  ' - coeffRes - Coefficient of restitution'                       &
                                                                  ,'perfRef', numberedmulti=.TRUE.)
CALL prms%CreateStringOption(       'Part-Boundary[$]-WallCoeffModel', 'Coefficients to be used. Options:.\n'                    //&
                                                                  ' - Tabakoff1981\n'                                            //&
                                                                  ' - Bons2017\n'                                                //&
                                                                  ' - Whitaker2018\n'                                            //&
                                                                  ' - Fong2019'                                                    &
                                                                            , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Boundary[$]-Young'    , "Young's modulus defining stiffness of wall material"            &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Boundary[$]-Poisson'  , "Poisson ratio defining relation of transverse to axial strain"  &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Boundary[$]-CoR'      , "Coefficent of restitution for normal velocity component"        &
                                                                , '1.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-YoungIC'   , "Young's modulus of particle defining stiffness of particle material"        &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-PoissonIC' , "Poisson ratio of particle defining relation of transverse to axial strain"  &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-YieldCoeff', "Yield strength defining elastic deformation"                    &
                                                                ,'0.'       , numberedmulti=.TRUE.)
! if nInit > 0 some variables have to be defined twice
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-YoungIC'   , "Young's modulus defining stiffness of particle material"&
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-PoissonIC' , "Poisson ratio defining relation of transverse to axial strain" &
                                                                , '0.'      , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Species[$]-Init[$]-YieldCoeff', "Yield strength defining elastic deformation"            &
                                                                ,'0.'       , numberedmulti=.TRUE.)

! Ambient condition ================================================================================================================
CALL prms%CreateLogicalOption(      'Part-Boundary[$]-AmbientCondition', 'Use ambient condition (condition "behind" boundary).'    &
                                                                            , numberedmulti=.TRUE.)
CALL prms%CreateLogicalOption(      'Part-Boundary[$]-AmbientConditionFix', 'TODO-DEFINE-PARAMETER'                                &
                                                                            , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Boundary[$]-AmbientVelo', 'Ambient velocity'                                             &
                                                                            , numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption(    'Part-Boundary[$]-WallVelo'   , 'Velocity (global x,y,z in [m/s]) of reflective particle'    //&
                                                                    ' boundary.'                                                   &
                                                                            , numberedmulti=.TRUE.)

CALL prms%CreateRealOption(         'Part-Boundary[$]-AmbientDens', 'Ambient density'                                              &
                                                                            , numberedmulti=.TRUE.)
CALL prms%CreateRealOption(         'Part-Boundary[$]-AmbientDynamicVisc' , 'Ambient dynamic viscosity'                            &
                                                                            , numberedmulti=.TRUE.)

! Call every other DefineParametersParticle routine
CALL DefineParametersParticleMesh()
CALL DefineParametersParticleInterpolation()
CALL DefineParametersParticleAnalyze()
CALL DefineParametersParticleBoundarySampling()
CALL DefineParametersErosionPoints()
#if USE_MPI
CALL DefineParametersLoadBalance()
CALL DefineParametersMPIShared()
#endif /*USE_MPI*/

END SUBROUTINE DefineParametersParticles


!===================================================================================================================================
! Global particle parameters needed for other particle inits
!===================================================================================================================================
SUBROUTINE InitParticleGlobals()
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_ReadInTools,                ONLY: GETINT,GETLOGICAL,GETINTFROMSTR,CountOption
USE MOD_Particle_Globals,           ONLY: PI
USE MOD_Particle_Interpolation_Vars,ONLY: DoInterpolation
USE MOD_Particle_Tracking_Vars,     ONLY: TrackingMethod
USE MOD_Particle_Vars,              ONLY: PDM
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

SWRITE(UNIT_stdOut,'(A)')' INIT PARTICLE GLOBALS...'

PDM%maxParticleNumber = GETINT('Part-maxParticleNumber','1')
PI                    = ACOS(-1.0D0)

! Find tracking method immediately, a lot of the later variables depend on it
TrackingMethod  = GETINTFROMSTR('TrackingMethod')
SELECT CASE(TrackingMethod)
  CASE(TRIATRACKING,TRACING,REFMAPPING)
    ! Valid tracking method, do nothing
  CASE DEFAULT
    SWRITE(UNIT_stdOut,'(A)')' TrackingMethod not implemented! Select refmapping (1), tracing (2) or triatracking (3).'
    CALL CollectiveStop(__STAMP__,'TrackingMethod not implemented! TrackingMethod=',IntInfo=TrackingMethod)
END SELECT

DoInterpolation       = GETLOGICAL('Part-DoInterpolation','.TRUE.')
IF (.NOT.DoInterpolation) &
  CALL CollectiveStop(__STAMP__,'Simulation without particle interpolation currently not supported!')

SWRITE(UNIT_stdOut,'(A)')' INIT PARTICLE GLOBALS DONE'

END SUBROUTINE InitParticleGlobals


!===================================================================================================================================
! Glue Subroutine for particle initialization
!===================================================================================================================================
!SUBROUTINE InitParticles(ManualTimeStep_opt)
SUBROUTINE InitParticles(doLoadBalance_opt)
! MODULES
USE MOD_Globals
USE Mod_Particle_Globals
USE MOD_ReadInTools
USE MOD_IO_HDF5,                    ONLY: AddToElemData
USE MOD_Part_Emission,              ONLY: InitializeParticleEmission
USE MOD_Particle_Analyze,           ONLY: InitParticleAnalyze
USE MOD_Particle_Boundary_Sampling, ONLY: RestartParticleBoundarySampling
USE MOD_Particle_Boundary_Vars
USE MOD_Particle_Restart,           ONLY: ParticleRestart
USE MOD_Particle_SGS,               ONLY: ParticleSGS
USE MOD_Particle_Surfaces,          ONLY: InitParticleSurfaces
USE MOD_Particle_Surface_Flux,      ONLY: InitializeParticleSurfaceflux
USE MOD_Particle_Tracking_Vars,     ONLY: TrackingMethod
USE MOD_Particle_Vars,              ONLY: ParticlesInitIsDone
#if USE_MPI
USE MOD_Particle_MPI,               ONLY: InitParticleCommSize
#endif
#if USE_RW
USE MOD_Particle_RandomWalk,        ONLY: ParticleInitRandomWalk
#endif
USE MOD_Particle_SGS,               ONLY: ParticleInitSGS
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!REAL,INTENT(IN),OPTIONAL       :: ManualTimeStep_opt                                             !> ManualTimeStep coming from Posti
LOGICAL,INTENT(IN),OPTIONAL      :: doLoadBalance_opt
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
IF(ParticlesInitIsDone)THEN
   SWRITE(*,*) "InitParticles already called."
   RETURN
END IF
!SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT PARTICLES...'

IF(TrackingMethod.NE.TRIATRACKING) THEN
  CALL InitParticleSurfaces()
END IF

!CALL InitializeVariables(ManualTimeStep_opt)
CALL InitializeVariables()
! InitRandomWalk must be called after InitializeVariables to know the size of TurbPartState
#if USE_RW
CALL ParticleInitRandomWalk()
#endif
! InitSGS must be called after InitRandomWalk and will abort FLEXI if an RW model is defined
CALL ParticleInitSGS()

! Requires information about initialized variables
CALL InitParticleAnalyze()

! Restart particles here, otherwise we can not know if we need to have an initial emission
IF (PRESENT(doLoadBalance_opt)) THEN
  CALL ParticleRestart(doFlushFiles=.FALSE.)
ELSE
  CALL ParticleRestart()
END IF
! Initialize emission. If no particles are present, assume restart from pure fluid and perform initial inserting
CALL InitializeParticleEmission()
! Initialize surface flux
CALL InitializeParticleSurfaceFlux()

#if USE_MPI
! has to be called AFTER InitializeVariables because we need to read the parameter file to know the CommSize
CALL InitParticleCommSize()

#endif

! Rebuild previous sampling on surfMesh
CALL RestartParticleBoundarySampling()

ParticlesInitIsDone=.TRUE.

SWRITE(UNIT_stdOut,'(A)')' INIT PARTICLES DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')
END SUBROUTINE InitParticles


!===================================================================================================================================
! Initialize the variables first
!===================================================================================================================================
!SUBROUTINE InitializeVariables(ManualTimeStep_opt)
SUBROUTINE InitializeVariables()
! MODULES
USE MOD_Globals
USE MOD_Particle_Globals
USE MOD_ReadInTools
USE MOD_Particle_Vars
USE MOD_Particle_Boundary_Sampling, ONLY: InitParticleBoundarySampling
USE MOD_Particle_Boundary_Vars ,ONLY: LowVeloRemove
USE MOD_Particle_Boundary_Vars ,ONLY: nAuxBCs
USE MOD_ErosionPoints          ,ONLY: InitErosionPoints
USE MOD_Particle_Interpolation ,ONLY: InitParticleInterpolation
USE MOD_Particle_Mesh          ,ONLY: GetMeshMinMax
USE MOD_Particle_Mesh          ,ONLY: InitParticleMesh
#if USE_MPI
USE MOD_Particle_MPI_Emission  ,ONLY: InitEmissionComm
USE MOD_Particle_MPI_Halo      ,ONLY: IdentifyPartExchangeProcs
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPI
#endif /*USE_MPI*/
USE MOD_Particle_Analyze_Vars  ,ONLY: RPP_Type, RPP_MaxBufferSize, RPP_Plane, RecordPart
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!REAL,INTENT(IN),OPTIONAL       :: ManualTimeStep_opt                                             !> ManualTimeStep coming from Posti
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: RPP_maxMemory, iP
REAL                  :: x_dummy(6)
!===================================================================================================================================
doPartIndex             = GETLOGICAL('doPartIndex','.FALSE.')
IF(doPartIndex) sumOfMatchedParticlesSpecies = 0
CALL AllocateParticleArrays()
CALL InitializeVariablesRandomNumbers()

! gravitational acceleration
PartGravity             = GETREALARRAY('Part-Gravity'          ,3  ,'0. , 0. , 0.')

! Number of species
nSpecies                = GETINT(     'Part-nSpecies','1')
! Abort if running particle code without any species
IF (nSpecies.LE.0) &
  CALL abort(__STAMP__,'ERROR: nSpecies .LE. 0:', nSpecies)
! Allocate species array
ALLOCATE(Species(1:nSpecies))
CALL InitializeVariablesSpeciesInits()

CALL InitializeVariablesPartBoundary()
! Flag if low velocity particles should be removed
LowVeloRemove       = GETLOGICAL('Part-LowVeloRemove','.FALSE.')

! Initialize record plane of particles
RecordPart          = GETLOGICAL('Part-RecordPart','.FALSE.')
IF (RecordPart) THEN
  ! Get type of record plane
  RPP_Type          = GETSTR('Part-RecordType','plane')
  ! Get size of buffer array
  RPP_maxMemory     = GETINT('Part-RecordMemory','100')           ! Max buffer (100MB)
  RPP_MaxBufferSize = RPP_MaxMemory*131072/6    != size in bytes/(real*RPP_maxMemory)

  SELECT CASE(RPP_Type)
    CASE('plane')
      ALLOCATE(RPP_Plane%RPP_Data(8,RPP_MaxBufferSize))
      RPP_Plane%RPP_Data = 0.
      x_dummy(1:6) = GETREALARRAY('Part-RPThresholds',6)
      DO iP=1,3
        RPP_Plane%x(1:2,iP)=x_dummy(1+2*(iP-1):2+2*(iP-1))
      END DO ! iPoint
      RPP_Plane%RPP_Records=0.
    CASE DEFAULT
      CALL abort(__STAMP__,'ERROR: Specified record plane does not exist!')
  END SELECT
END IF

! AuxBCs
nAuxBCs=GETINT('Part-nAuxBCs','0')
CALL InitializeVariablesAuxBC()

! CALL InitializeVariablesTimeStep(ManualTimeStep_opt)
CALL InitializeVariablesTimeStep()

! Build BGM and initialize particle mesh
CALL InitParticleMesh()
#if USE_MPI
!-- Build MPI communication
CALL IdentifyPartExchangeProcs()
#endif

! Initialize surface sampling
CALL InitParticleBoundarySampling()

! Initialize impact recording
CALL InitErosionPoints()

! Initialize interpolation and particle-in-cell for field -> particle coupling
!--> Could not be called earlier because a halo region has to be build depending on the given BCs
CALL InitParticleInterpolation()

! Initialize MPI communicator for emmission procs
#if USE_MPI
CALL InitEmissionComm()
CALL MPI_BARRIER(PartMPI%COMM,IERROR)
#endif /*MPI*/

SWRITE(UNIT_StdOut,'(132("-"))')

END SUBROUTINE InitializeVariables


SUBROUTINE AllocateParticleArrays()
!===================================================================================================================================
! Initialize the variables first
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_ReadInTools
USE MOD_Particle_Vars
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: ALLOCSTAT
!===================================================================================================================================
! Allocate array to hold particle properties
ALLOCATE(PartState(       1:6,1:PDM%maxParticleNumber),    &
         PartReflCount(       1:PDM%maxParticleNumber),    &
         LastPartPos(     1:3,1:PDM%maxParticleNumber),    &
         PartPosRef(      1:3,1:PDM%MaxParticleNumber),    &
         PartSpecies(         1:PDM%maxParticleNumber),    &
! Allocate array for Runge-Kutta time stepping
         Pt(              1:3,1:PDM%maxParticleNumber),    &
         Pt_temp(         1:6,1:PDM%maxParticleNumber),    &
! Allocate array for particle position in reference coordinates
         PDM%ParticleInside(  1:PDM%maxParticleNumber),    &
         PDM%nextFreePosition(1:PDM%maxParticleNumber),    &
         PDM%IsNewPart(       1:PDM%maxParticleNumber),    &
! Allocate particle-to-element-mapping (PEM) arrays
         PEM%Element(         1:PDM%maxParticleNumber),    &
         PEM%lastElement(     1:PDM%maxParticleNumber),    &
         STAT=ALLOCSTAT)
IF(doPartIndex) ALLOCATE(PartIndex(1:PDM%maxParticleNumber), STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) &
  CALL abort(__STAMP__,'ERROR in particle_init.f90: Cannot allocate particle arrays!')

PDM%ParticleInside(1:PDM%maxParticleNumber)  = .FALSE.
PDM%IsNewPart(     1:PDM%maxParticleNumber)  = .FALSE.
LastPartPos(   1:3,1:PDM%maxParticleNumber)  = 0.
PartState                                    = 0.
PartReflCount                                = 0.
Pt                                           = 0.
PartSpecies                                  = 0
IF(doPartIndex) PartIndex                    = 0
PDM%nextFreePosition(1:PDM%maxParticleNumber)= 0
Pt_temp                                      = 0
PartPosRef                                   =-888.

END SUBROUTINE AllocateParticleArrays


SUBROUTINE InitializeVariablesRandomNumbers()
!===================================================================================================================================
! Initialize the variables first
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_ReadInTools
USE MOD_Particle_Vars
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iSeed, nRandomSeeds,SeedSize
CHARACTER(32)         :: hilf
!===================================================================================================================================
!--- initialize randomization
! Read print flags
nRandomSeeds = GETINT('Part-NumberOfRandomSeeds','0')
! specifies compiler specific minimum number of seeds
CALL RANDOM_SEED(Size = SeedSize)

ALLOCATE(Seeds(SeedSize))
! to ensure a solid run when an unfitting number of seeds is provided in ini
Seeds(:)=1
IF(nRandomSeeds.EQ.-1) THEN
  ! ensures different random numbers through irreproducable random seeds (via System_clock)
  CALL InitRandomSeed(nRandomSeeds,SeedSize,Seeds)
ELSE IF(nRandomSeeds.EQ.0) THEN
 !   IF (Restart) THEN
 !   CALL !numbers from state file
 ! ELSE IF (.NOT.Restart) THEN
  CALL InitRandomSeed(nRandomSeeds,SeedSize,Seeds)
ELSE IF(nRandomSeeds.GT.0) THEN
  ! read in numbers from ini
  IF(nRandomSeeds.NE.SeedSize) THEN
    SWRITE (UNIT_StdOut,'(A,I0,A,I0,A)') ' | Expected ',SeedSize,' seeds. Provided ', nRandomSeeds ,&
                                         '. Computer uses default value for all unset values.'
  END IF

  DO iSeed=1,MIN(SeedSize,nRandomSeeds)
    WRITE(UNIT=hilf,FMT='(I0)') iSeed
    Seeds(iSeed)= GETINT('Part-RandomSeed'//TRIM(hilf))
  END DO

  IF (ALL(Seeds(:).EQ.0)) CALL ABORT(__STAMP__,'Not all seeds can be set to zero ')
  CALL InitRandomSeed(nRandomSeeds,SeedSize,Seeds)
ELSE
  SWRITE (*,*) 'Error: nRandomSeeds not defined.'//&
  'Choose nRandomSeeds'//&
  '=-1    pseudo random'//&
  '= 0    hard-coded deterministic numbers'//&
  '> 0    numbers from ini. Expected ',SeedSize,'seeds.'
END IF

END SUBROUTINE InitializeVariablesRandomNumbers


SUBROUTINE InitializeVariablesSpeciesInits()
!===================================================================================================================================
! Initialize the variables first
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Globals
USE MOD_ReadInTools
USE MOD_Particle_Vars
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iSpec,iInit,iExclude
CHARACTER(32)         :: tmpStr,tmpStr2,tmpStr3
!===================================================================================================================================
! Loop over all species and get requested data
DO iSpec = 1, nSpecies
  SWRITE(UNIT_StdOut,'(66("-"))')
  WRITE(UNIT=tmpStr,FMT='(I2)') iSpec

  ! Get number of requested inits
  Species(iSpec)%NumberOfInits         = GETINT('Part-Species'//TRIM(ADJUSTL(tmpStr))//'-nInits','0')
  ALLOCATE(Species(iSpec)%Init(0:Species(iSpec)%NumberOfInits))

  ! get species values // only once
  !--> General Species Values
  SWRITE(UNIT_StdOut,'(A,I0,A,I0)') ' | Reading general  particle properties for Species',iSpec,'-Init',iInit
  Species(iSpec)%RHSMethod             = GETINTFROMSTR('Part-Species'//TRIM(ADJUSTL(tmpStr))//'-RHSMethod'             )
  Species(iSpec)%MassIC                = GETREAL(      'Part-Species'//TRIM(ADJUSTL(tmpStr))//'-MassIC'           ,'0.')
  Species(iSpec)%DiameterIC            = GETREAL(      'Part-Species'//TRIM(ADJUSTL(tmpStr))//'-DiameterIC'       ,'0.')
  Species(iSpec)%DensityIC             = GETREAL(      'Part-Species'//TRIM(ADJUSTL(tmpStr))//'-DensityIC'        ,'0.')
  IF (Species(iSpec)%MassIC .EQ. 0.) THEN
    Species(iSpec)%MassIC=Species(iSpec)%DensityIC*PI/6*Species(iSpec)%DiameterIC**3
    SWRITE(UNIT_StdOut,'(A,I0,A,F16.5)') ' | Mass of species (spherical) ', iSpec, ' = ', Species(iSpec)%MassIC
  END IF
  Species(iSpec)%LowVeloThreshold      = GETREAL(      'Part-Species'//TRIM(ADJUSTL(tmpStr))//'-LowVeloThreshold' ,'0.')
  Species(iSpec)%HighVeloThreshold     = GETREAL(      'Part-Species'//TRIM(ADJUSTL(tmpStr))//'-HighVeloThreshold','0.')

  !--> Bons particle rebound model
  SWRITE(UNIT_StdOut,'(A,I0,A,I0)') ' | Reading rebound  particle properties for Species',iSpec,'-Init',iInit
  Species(iSpec)%YoungIC               = GETREAL(      'Part-Species'//TRIM(ADJUSTL(tmpStr))//'-YoungIC'          ,'0.')
  Species(iSpec)%PoissonIC             = GETREAL(      'Part-Species'//TRIM(ADJUSTL(tmpStr))//'-PoissonIC'        ,'0.')
  Species(iSpec)%YieldCoeff            = GETREAL(      'Part-Species'//TRIM(ADJUSTL(tmpStr))//'-YieldCoeff'       ,'0.')

  !-- Check if particles have valid mass/density
  IF (Species(iSpec)%MassIC .LE. 0.    .AND..NOT.(Species(iSpec)%RHSMethod.EQ.RHS_NONE          &
                                       .OR.       Species(iSpec)%RHSMethod.EQ.RHS_TRACER        &
                                       .OR.       Species(iSpec)%RHSMethod.EQ.RHS_CONVERGENCE)) &
    CALL CollectiveStop(__STAMP__, 'Invalid particle mass given, Species=',IntInfo=iSpec)

  IF (Species(iSpec)%DensityIC .LE. 0. .AND..NOT.(Species(iSpec)%RHSMethod.EQ.RHS_NONE          &
                                       .OR.       Species(iSpec)%RHSMethod.EQ.RHS_TRACER        &
                                       .OR.       Species(iSpec)%RHSMethod.EQ.RHS_CONVERGENCE)) &
    CALL CollectiveStop(__STAMP__, 'Invalid particle density given, Species=',IntInfo=iSpec)

  ! Loop over all inits and get requested data
  DO iInit = 0, Species(iSpec)%NumberOfInits
    ! set help characters to read strings from parameter file
    IF(iInit.EQ.0)THEN
      tmpStr2=TRIM(ADJUSTL(tmpStr))
    ELSE ! iInit >0
      WRITE(UNIT=tmpStr2,FMT='(I0)') iInit
      tmpStr2=TRIM(ADJUSTL(tmpStr))//'-Init'//TRIM(ADJUSTL(tmpStr2))
    END IF ! iInit

    ! Emission and init data
    SWRITE(UNIT_StdOut,'(A,I0,A,I0)') ' | Reading emission particle properties for Species',iSpec,'-Init',iInit
    Species(iSpec)%Init(iInit)%UseForInit            = GETLOGICAL(  'Part-Species'//TRIM(tmpStr2)//'-UseForInit'            ,'.TRUE.')
    Species(iSpec)%Init(iInit)%UseForEmission        = GETLOGICAL(  'Part-Species'//TRIM(tmpStr2)//'-UseForEmission'        ,'.TRUE.')
    Species(iSpec)%Init(iInit)%initialParticleNumber = GETINT(      'Part-Species'//TRIM(tmpStr2)//'-initialParticleNumber' ,'0')
    Species(iSpec)%Init(iInit)%ParticleEmissionType  = GETINT(      'Part-Species'//TRIM(tmpStr2)//'-ParticleEmissionType'  ,'1')
    Species(iSpec)%Init(iInit)%ParticleEmission      = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-ParticleEmission'      ,'0.')
    Species(iSpec)%Init(iInit)%ParticleEmissionTime  = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-ParticleEmissionTime'  ,'1.')
    Species(iSpec)%Init(iInit)%PartDensity           = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-PartDensity'           ,'0.')
    Species(iSpec)%Init(iInit)%SpaceIC               = TRIM(GETSTR( 'Part-Species'//TRIM(tmpStr2)//'-SpaceIC'               ,'cuboid'))
    Species(iSpec)%Init(iInit)%VeloVecIC             = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-VeloVecIC'           ,3,'0. , 0. , 0.')
    Species(iSpec)%Init(iInit)%VeloIC                = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-VeloIC'                ,'0.')
    Species(iSpec)%Init(iInit)%VeloTurbIC            = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-VeloTurbIC'            ,'0.')
    Species(iSpec)%Init(iInit)%velocityDistribution  = TRIM(GETSTR( 'Part-Species'//TRIM(tmpStr2)//'-velocityDistribution'  ,'constant'))
    Species(iSpec)%Init(iInit)%InflowRiseTime        = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-InflowRiseTime'        ,'0.')
    Species(iSpec)%Init(iInit)%NumberOfExcludeRegions= GETINT(      'Part-Species'//TRIM(tmpStr2)//'-NumberOfExcludeRegions','0')

    !> Read only emission properties required for SpaceIC
    !>>> Parameters must be set to false to allow conformity checks afterwards
    Species(iSpec)%Init(iInit)%CalcHeightFromDt = .FALSE.

    ! Set unique part index
    IF (doPartIndex) Species(iSpec)%Init(iInit)%CountIndex = 0.

    SELECT CASE(Species(iSpec)%Init(iInit)%SpaceIC)
      CASE('point')
        Species(iSpec)%Init(iInit)%BasePointIC       = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BasePointIC'   ,3,'0. , 0. , 0.')
      CASE('line','line_with_equidistant_distribution')
        Species(iSpec)%Init(iInit)%BasePointIC       = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BasePointIC'   ,3,'0. , 0. , 0.')
        Species(iSpec)%Init(iInit)%BaseVector1IC     = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BaseVector1IC' ,3,'1. , 0. , 0.')
      CASE('disc')
        Species(iSpec)%Init(iInit)%BasePointIC       = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BasePointIC'   ,3,'0. , 0. , 0.')
        Species(iSpec)%Init(iInit)%RadiusIC          = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-RadiusIC'      ,'1.')
        Species(iSpec)%Init(iInit)%NormalIC          = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-NormalIC'      ,3,'0. , 0. , 1.')
      CASE('circle', 'circle_equidistant')
        Species(iSpec)%Init(iInit)%BasePointIC       = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BasePointIC'   ,3,'0. , 0. , 0.')
        Species(iSpec)%Init(iInit)%RadiusIC          = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-RadiusIC'        ,'1.')
        Species(iSpec)%Init(iInit)%NormalIC          = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-NormalIC'      ,3,'0. , 0. , 1.')
      CASE('cuboid')
        Species(iSpec)%Init(iInit)%BasePointIC       = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BasePointIC'   ,3,'0. , 0. , 0.')
        Species(iSpec)%Init(iInit)%BaseVector1IC     = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BaseVector1IC' ,3,'1. , 0. , 0.')
        Species(iSpec)%Init(iInit)%BaseVector2IC     = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BaseVector2IC' ,3,'0. , 1. , 0.')
        Species(iSpec)%Init(iInit)%CuboidHeightIC    = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-CuboidHeightIC'  ,'1.')
        Species(iSpec)%Init(iInit)%CalcHeightFromDt  = GETLOGICAL(  'Part-Species'//TRIM(tmpStr2)//'-CalcHeightFromDt','.FALSE.')
      CASE('cylinder')
        Species(iSpec)%Init(iInit)%BasePointIC       = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BasePointIC'   ,3,'0. , 0. , 0.')
        Species(iSpec)%Init(iInit)%BaseVector1IC     = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BaseVector1IC' ,3,'1. , 0. , 0.')
        Species(iSpec)%Init(iInit)%BaseVector2IC     = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BaseVector2IC' ,3,'0. , 1. , 0.')
        Species(iSpec)%Init(iInit)%CylinderHeightIC  = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-CylinderHeightIC','1.')
      CASE('sphere')
        Species(iSpec)%Init(iInit)%BasePointIC       = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BasePointIC'   ,3,'0. , 0. , 0.')
        Species(iSpec)%Init(iInit)%RadiusIC          = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-RadiusIC'        ,'1.')
      CASE('Gaussian')
        Species(iSpec)%Init(iInit)%BasePointIC       = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-BasePointIC'   ,3,'0. , 0. , 0.')
        Species(iSpec)%Init(iInit)%BaseVariance      = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-BaseVariance'    ,'1.')
        Species(iSpec)%Init(iInit)%RadiusIC          = GETREAL(     'Part-Species'//TRIM(tmpStr2)//'-RadiusIC'        ,'1.')
        Species(iSpec)%Init(iInit)%NormalIC          = GETREALARRAY('Part-Species'//TRIM(tmpStr2)//'-NormalIC'      ,3,'0. , 0. , 1.')
!      CASE('sin_deviation')
        ! Currently not implemented
      CASE DEFAULT
        CALL ABORT(__STAMP__,'Unknown particle emission type')
    END SELECT


    ! Nullify additional init data here
    Species(iSpec)%Init(iInit)%InsertedParticle      = 0
    Species(iSpec)%Init(iInit)%InsertedParticleSurplus = 0

    ! Get absolute value of particle velocity vector and normalize the VeloVecIC vector
    IF (Species(iSpec)%Init(iInit)%VeloIC.EQ.0.) THEN
      Species(iSpec)%Init(iInit)%VeloIC                = VECNORM(Species(iSpec)%Init(iInit)%VeloVecIC(1:3))
    END IF

    ! Only normalize if the vector does not have zero length. If it has, our job is done
    IF (VECNORM(Species(iSpec)%Init(iInit)%VeloVecIC(1:3)).NE.0) THEN
      Species(iSpec)%Init(iInit)%VeloVecIC             = Species(iSpec)%Init(iInit)%VeloVecIC/VECNORM(Species(iSpec)%Init(iInit)%VeloVecIC(1:3))
    END IF

    !----------- various checks/calculations after read-in of Species(i)%Init(iInit)%-data ----------------------------------!

    !--- Check if Initial ParticleInserting is really used
    IF (Species(iSpec)%Init(iInit)%UseForInit                   .AND. &
       (Species(iSpec)%Init(iInit)%initialParticleNumber.EQ.0)) THEN
      Species(iSpec)%Init(iInit)%UseForInit = .FALSE.
      SWRITE(UNIT_StdOut,'(A,I0,A,I0,A)',ADVANCE='NO') ' | WARNING: Species',iSpec,'-Init',iInit,' - no ParticleNumber detected,'
      SWRITE(UNIT_StdOut,'(A)')                        ' disabling initial particle inserting!'
    END IF

    !--- Check if ParticleEmission is really used
    IF (Species(iSpec)%Init(iInit)%UseForEmission         .AND. &
       (Species(iSpec)%Init(iInit)%ParticleEmission.EQ.0)) THEN
      Species(iSpec)%Init(iInit)%UseForEmission = .FALSE.
      SWRITE(UNIT_StdOut,'(A,I0,A,I0,A)',ADVANCE='NO') ' | WARNING: Species',iSpec,'-Init',iInit,' - no emission rate  detected,'
      SWRITE(UNIT_StdOut,'(A)')                        ' disabling particle emission!'
    END IF

    !--- cuboid-/cylinder-height calculation from v and dt
    SELECT CASE(Species(iSpec)%Init(iInit)%SpaceIC)
      CASE('cuboid')
        IF (.NOT.Species(iSpec)%Init(iInit)%CalcHeightFromDt) THEN
          IF (ALMOSTEQUAL(Species(iSpec)%Init(iInit)%CuboidHeightIC,-1.)) THEN
            Species(iSpec)%Init(iInit)%CalcHeightFromDt=.TRUE.
            SWRITE(*,*) "WARNING: Cuboid height will be calculated from v and dt!"
          END IF
        END IF

      CASE('cylinder')
        IF (.NOT.Species(iSpec)%Init(iInit)%CalcHeightFromDt) THEN
          IF (ALMOSTEQUAL(Species(iSpec)%Init(iInit)%CylinderHeightIC,-1.)) THEN
            Species(iSpec)%Init(iInit)%CalcHeightFromDt=.TRUE.
            SWRITE(*,*) "WARNING: Cylinder height will be calculated from v and dt!"
          END IF
        END IF

      CASE DEFAULT
        IF (Species(iSpec)%Init(iInit)%CalcHeightFromDt) THEN
          CALL abort(__STAMP__,' Calculating height from v and dt is only supported for cuboid or cylinder!')
        END IF
    END SELECT

    IF (Species(iSpec)%Init(iInit)%CalcHeightFromDt) THEN
      IF (Species(iSpec)%Init(iInit)%UseForInit) THEN
        CALL abort(__STAMP__,' Calculating height from v and dt is not supported for initial ParticleInserting!')
      END IF
    END IF

    !--- read ExcludeRegions and normalize/calculate corresponding vectors
    IF (Species(iSpec)%Init(iInit)%NumberOfExcludeRegions.GT.0) THEN
      ALLOCATE(Species(iSpec)%Init(iInit)%ExcludeRegion(1:Species(iSpec)%Init(iInit)%NumberOfExcludeRegions))

      IF  ((TRIM(Species(iSpec)%Init(iInit)%SpaceIC).EQ.'cuboid') &
       .OR.(TRIM(Species(iSpec)%Init(iInit)%SpaceIC).EQ.'cylinder')) THEN

        ! Read in information for exclude regions
        DO iExclude=1,Species(iSpec)%Init(iInit)%NumberOfExcludeRegions
          WRITE(UNIT=tmpStr3,FMT='(I0)') iExclude
          tmpStr3=TRIM(tmpStr2)//'-ExcludeRegion'//TRIM(tmpStr3)
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%SpaceIC              &
            = TRIM(GETSTR('Part-Species'//TRIM(tmpStr3)//'-SpaceIC','cuboid'))
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%RadiusIC             &
            = GETREAL(    'Part-Species'//TRIM(tmpStr3)//'-RadiusIC','1.')
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%Radius2IC            &
            = GETREAL(    'Part-Species'//TRIM(tmpStr3)//'-Radius2IC','0.')
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC             &
            = GETREALARRAY('Part-Species'//TRIM(tmpStr3)//'-NormalIC',3,'0. , 0. , 1.')
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BasePointIC          &
            = GETREALARRAY('Part-Species'//TRIM(tmpStr3)//'-BasePointIC',3,'0. , 0. , 0.')
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC        &
            = GETREALARRAY('Part-Species'//TRIM(tmpStr3)//'-BaseVector1IC',3,'1. , 0. , 0.')
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC        &
            = GETREALARRAY('Part-Species'//TRIM(tmpStr3)//'-BaseVector2IC',3,'0. , 1. , 0.')
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%CuboidHeightIC       &
            = GETREAL(     'Part-Species'//TRIM(tmpStr3)//'-CuboidHeightIC','1.')
          Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%CylinderHeightIC     &
            = GETREAL(     'Part-Species'//TRIM(tmpStr3)//'-CylinderHeightIC','1.')

          !--check and normalize data
          IF ((TRIM(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%SpaceIC).EQ.'cuboid') .OR.             &
               ((((.NOT.ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(1),1.)   &
              .OR. .NOT.ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(2),0.))  &
              .OR. .NOT.ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(3),0.))  &
            .OR. ((.NOT.ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(1),0.)   &
              .OR. .NOT.ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(2),1.))  &
              .OR. .NOT.ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(3),0.))) &
            .AND.    (((ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC     (1),0.))  &
              .AND.    (ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC     (2),0.))) &
              .AND.    (ALMOSTEQUAL(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC     (3),1.))))) THEN
            !-- cuboid; or BV are non-default and NormalIC is default: calc. NormalIC for ExcludeRegions from BV1/2
            !   (for def. BV and non-def. NormalIC; or all def. or non-def.: Use User-defined NormalIC when ExclRegion is cylinder)
            Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(1)                  &
              = Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(2)         &
              * Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(3)         &
              - Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(3)         &
              * Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(2)
            Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(2)                  &
              = Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(3)         &
              * Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(1)         &
              - Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(1)         &
              * Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(3)
            Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(3)                  &
              = Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(1)         &
              * Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(2)         &
              - Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(2)         &
              * Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(1)
          ELSE IF ( (TRIM(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%SpaceIC).NE.'cuboid')    .AND. &
                    (TRIM(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%SpaceIC).NE.'cylinder')) THEN
            CALL abort(__STAMP__,'Error in ParticleInit, ExcludeRegions must be cuboid or cylinder!')
          END IF

          IF (Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(1)**2 +           &
              Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(2)**2 +           &
              Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(3)**2 .GT. 0.) THEN
            Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC                     &
              = Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC                 &
              / SQRT(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(1)**2      &
              + Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(2)**2           &
              + Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%NormalIC(3)**2)
            Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%ExcludeBV_lenghts(1)         &
              = SQRT(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(1)**2 &
              + Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(2)**2      &
              + Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector1IC(3)**2)
            Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%ExcludeBV_lenghts(2)         &
              = SQRT(Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(1)**2 &
              + Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(2)**2      &
              + Species(iSpec)%Init(iInit)%ExcludeRegion(iExclude)%BaseVector2IC(3)**2)
          ELSE
            CALL abort(__STAMP__,'Error in ParticleInit, NormalIC Vector must not be zero!')
          END IF
        END DO !iExclude

      ! invalid combination of SpaceIC and exclude region
      ELSE
        CALL abort(__STAMP__,'Error in ParticleInit, ExcludeRegions are currently only implemented for the SpaceIC cuboid or cylinder!')
      END IF
    END IF

    !--- determine StartnumberOfInits (start loop index, e.g., for emission loops)
    !--> two options:
    !->> old option: format Part-Species(i)-***
    !->> new option: format Part-Species(i)-Init(i)-***
    IF(iInit.EQ.0)THEN
      ! only new style paramaters defined
      IF   (((Species(iSpec)%Init(iInit)%initialParticleNumber .EQ. 0 )  &
        .AND.(Species(iSpec)%Init(iInit)%ParticleEmission      .EQ. 0.)) &
        .AND.(Species(iSpec)%NumberOfInits                     .GT. 0 )) THEN
        Species(iSpec)%StartnumberOfInits = 1
      ELSE
        ! old style parameters has been defined for inits/emissions
        Species(iSpec)%StartnumberOfInits = 0
      END IF
      SWRITE(UNIT_StdOut,'(A,I0,A,I0)') ' | StartNumberOfInits of Species ', iSpec, ' = ', Species(iSpec)%StartnumberOfInits
    END IF ! iInit .EQ.0

  END DO ! iInit
END DO ! iSpec

END SUBROUTINE InitializeVariablesSpeciesInits


SUBROUTINE InitializeVariablesPartBoundary()
!===================================================================================================================================
! Initialize the variables first
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Mesh_Vars              ,ONLY: BoundaryName,BoundaryType,nBCs
USE MOD_Particle_Boundary_Vars ,ONLY: PartBound,nPartBound
!USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_Particle_Surfaces_Vars ,ONLY: BCdata_auxSF
USE MOD_Particle_Vars
USE MOD_ReadInTools
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iBC
CHARACTER(32)         :: tmpStr
CHARACTER(200)        :: tmpString
!INTEGER               :: ALLOCSTAT
CHARACTER(200), ALLOCATABLE :: tmpStringBC(:)
!===================================================================================================================================
! Read in boundary parameters
! Leave out this check in FLEXI even though we should probably do it
!dummy_int  = CountOption('Part-nBounds')       ! check if Part-nBounds is present in .ini file

! get number of particle boundaries
nPartBound = CountOption('Part-BoundaryName')

! if no part boundaries are given, assume the same number as for the DG part
IF (nPartBound.EQ.0) THEN
  nPartBound = nBCs
END IF

SWRITE(UNIT_StdOut,'(132("."))')
SWRITE(UNIT_StdOut,'(A)') ' | Reading particle boundary properties'

! Allocate arrays for particle boundaries
ALLOCATE(PartBound%SourceBoundName    (1:nBCs))
ALLOCATE(PartBound%SourceBoundType    (1:nBCs))
ALLOCATE(PartBound%TargetBoundCond    (1:nBCs))
ALLOCATE(PartBound%WallTemp           (1:nBCs))
ALLOCATE(PartBound%WallVelo       (1:3,1:nBCs))
ALLOCATE(PartBound%WallModel          (1:nBCs))
ALLOCATE(PartBound%WallCoeffModel     (1:nBCs))
!ALLOCATE(PartBound%AmbientCondition   (1:nBCs))
!ALLOCATE(PartBound%AmbientConditionFix(1:nBCs))
!ALLOCATE(PartBound%AmbientTemp        (1:nBCs))
!ALLOCATE(PartBound%AmbientVelo    (1:3,1:nBCs))
!ALLOCATE(PartBound%AmbientDens        (1:nBCs))
!ALLOCATE(PartBound%AmbientDynamicVisc (1:nBCs))

! Bons particle rebound model
ALLOCATE(PartBound%Young              (1:nBCs))
ALLOCATE(PartBound%Poisson            (1:nBCs))

! Fong coefficent of restitution
ALLOCATE(PartBound%CoR                (1:nBCs))
ALLOCATE(tmpStringBC                  (1:nBCs))

! Surface Flux
ALLOCATE(BCdata_auxSF                 (1:nBCs))
DO iBC=1,nBCs
  ! init value when not used
  BCdata_auxSF(iBC)%SideNumber = -1
  BCdata_auxSF(iBC)%GlobalArea = 0.
  BCdata_auxSF(iBC)%LocalArea  = 0.
END DO

! Loop over all particle boundaries and get information
!DO iPartBound=1,nPartBound
!  tmpStringBC(iPartBound) = TRIM(GETSTR('Part-BoundaryName'))
!END DO

!GEO%nPeriodicVectors = 0

DO iBC = 1,nBCs
  IF (BoundaryType(iBC,1).EQ.0) THEN
    PartBound%TargetBoundCond(iBC) = -1
    SWRITE(*,*)"... PartBound",iBC,"is internal bound, no mapping needed"
    CYCLE
  END IF

  SELECT CASE (BoundaryType(iBC, BC_TYPE))
   CASE(1)
     tmpString = 'periodic'
!     GEO%nPeriodicVectors = GEO%nPeriodicVectors+1
!   CASE(2,12,22)
!     tmpString='open'
   CASE(3,4)
     tmpString = 'reflective'
   CASE(9)
     tmpString = 'symmetry'
   CASE DEFAULT
     tmpString = 'open'
  END SELECT

  WRITE(UNIT=tmpStr,FMT='(I0)') iBC
  PartBound%SourceBoundType(iBC) = TRIM(GETSTR('Part-Boundary'//TRIM(tmpStr)//'-Type', tmpString))
  PartBound%SourceBoundName(iBC) = TRIM(GETSTR('Part-Boundary'//TRIM(tmpStr)//'-Name', BoundaryName(iBC))) !tmpStringBC(iPartBound)
  ! Select boundary condition for particles
  SELECT CASE (PartBound%SourceBoundType(iBC))
    ! Inflow / outflow
    CASE('open')
      PartBound%TargetBoundCond(iBC)      = PartBound%OpenBC
!      PartBound%AmbientCondition(iBC)     = GETLOGICAL(  'Part-Boundary'//TRIM(tmpStr)//'-AmbientCondition'   ,'.FALSE.')
!      IF(PartBound%AmbientCondition(iBC)) THEN
!        PartBound%AmbientConditionFix(iBC)= GETLOGICAL(  'Part-Boundary'//TRIM(tmpStr)//'-AmbientConditionFix','.TRUE.')
!        PartBound%AmbientVelo(1:3,iBC)    = GETREALARRAY('Part-Boundary'//TRIM(tmpStr)//'-AmbientVelo'      ,3,'0., 0., 0.')
!        PartBound%AmbientDens(iBC)        = GETREAL(     'Part-Boundary'//TRIM(tmpStr)//'-AmbientDens'        ,'0')
!        PartBound%AmbientDynamicVisc(iBC) = GETREAL(     'Part-Boundary'//TRIM(tmpStr)//'-AmbientDynamicVisc' ,'1.72326582572253E-5') ! N2:T=288K
!      END IF

    ! Reflective (wall)
    CASE('reflective')
      PartBound%TargetBoundCond(iBC)      = PartBound%ReflectiveBC
      PartBound%WallVelo(1:3,iBC)         = GETREALARRAY('Part-Boundary'//TRIM(tmpStr)//'-WallVelo'         ,3,'0. , 0. , 0.')
      PartBound%WallModel(iBC)            = GETSTR(      'Part-Boundary'//TRIM(tmpStr)//'-WallModel'          ,'perfRef')

      ! Non-perfect reflection
      IF (PartBound%WallModel(iBC).EQ.'coeffRes') THEN
          PartBound%WallCoeffModel(iBC)   = GETSTR(      'Part-Boundary'//TRIM(tmpStr)//'-WallCoeffModel'     ,'Tabakoff1981')

          SELECT CASE(PartBound%WallCoeffModel(iBC))
            ! Bons particle rebound model
            CASE ('Bons2017','Whitaker2018')
              PartBound%Young(iBC)        = GETREAL(     'Part-Boundary'//TRIM(tmpStr)//'-Young')
              PartBound%Poisson(iBC)      = GETREAL(     'Part-Boundary'//TRIM(tmpStr)//'-Poisson')

            ! Fong coefficient of reflection
            CASE('Fong2019')
              PartBound%CoR(iBC)          = GETREAL(     'Part-Boundary'//TRIM(tmpStr)//'-CoR'                ,'1.')

            ! Different CoR per direction
            CASE('Tabakoff1981','Grant1975')
              ! nothing to reading

            CASE DEFAULT
              CALL CollectiveSTOP(__STAMP__,'Unknown wall model given!')

          END SELECT
      END IF

    ! Periodic
    CASE('periodic')
      PartBound%TargetBoundCond(iBC)      = PartBound%PeriodicBC

    CASE('symmetry')
      PartBound%TargetBoundCond(iBC)      = PartBound%SymmetryBC

    ! Invalid boundary option
    CASE DEFAULT
      SWRITE(*,*) ' Boundary does not exists: ', TRIM(PartBound%SourceBoundType(iBC))
      CALL abort(__STAMP__,'Particle Boundary Condition does not exist')
  END SELECT
END DO

!GEO%nPeriodicVectors = GEO%nPeriodicVectors/2

SDEALLOCATE(tmpStringBC)

END SUBROUTINE InitializeVariablesPartBoundary


SUBROUTINE InitializeVariablesAuxBC()
!===================================================================================================================================
! Initialize the variables first
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_ReadInTools
USE MOD_Particle_Globals       ,ONLY: PI,ALMOSTZERO
USE MOD_Particle_Boundary_Vars ,ONLY: PartAuxBC
USE MOD_Particle_Boundary_Vars ,ONLY: nAuxBCs,AuxBCType,AuxBCMap,AuxBC_plane,AuxBC_cylinder,AuxBC_cone,AuxBC_parabol,UseAuxBCs
USE MOD_Particle_Mesh          ,ONLY: MarkAuxBCElems
USE MOD_Particle_Vars
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iAuxBC, nAuxBCplanes, nAuxBCcylinders, nAuxBCcones, nAuxBCparabols
INTEGER               :: iPartBound
CHARACTER(32)         :: tmpStr,tmpStr2
CHARACTER(200)        :: tmpString
REAL                  :: n_vec(3), cos2, rmax
REAL, DIMENSION(3,1)  :: n,n1,n2
REAL, DIMENSION(3,3)  :: rot1, rot2
REAL                  :: alpha1, alpha2
!===================================================================================================================================
!--> Only read anything if there are auxiliary BCs
IF (nAuxBCs.GT.0) THEN
  UseAuxBCs=.TRUE.
  ALLOCATE (AuxBCType(1:nAuxBCs) &
            ,AuxBCMap(1:nAuxBCs) )
  AuxBCMap=0

  !- Read in BC parameters
  ALLOCATE(PartAuxBC%TargetBoundCond  (1:nAuxBCs))
  ALLOCATE(PartAuxBC%MomentumACC      (1:nAuxBCs))
  ALLOCATE(PartAuxBC%WallTemp         (1:nAuxBCs))
  ALLOCATE(PartAuxBC%WallVelo     (1:3,1:nAuxBCs))

  ! Get auxiliary boundary types
  DO iPartBound=1,nAuxBCs
    WRITE(UNIT=tmpStr,FMT='(I0)') iPartBound
    tmpString = TRIM(GETSTR('Part-AuxBC'//TRIM(tmpStr)//'-Condition','open'))

    SELECT CASE (TRIM(tmpString))

    ! Inflow / outflow
    CASE('open')
      PartAuxBC%TargetBoundCond(iPartBound) = PartAuxBC%OpenBC

    ! Reflective (wall)
    CASE('reflective')
      PartAuxBC%TargetBoundCond(iPartBound) = PartAuxBC%ReflectiveBC
      PartAuxBC%MomentumACC(iPartBound)     = GETREAL(     'Part-AuxBC'//TRIM(tmpStr)//'-MomentumACC','0')
      PartAuxBC%WallTemp(iPartBound)        = GETREAL(     'Part-AuxBC'//TRIM(tmpStr)//'-WallTemp','0')
      PartAuxBC%WallVelo(1:3,iPartBound)    = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-WallVelo',3,'0. , 0. , 0.')

    ! Unknown auxiliary boundary type
    CASE DEFAULT
      SWRITE(*,*) ' AuxBC Condition does not exists: ', TRIM(tmpString)
      CALL abort(__STAMP__,'AuxBC Condition does not exist')

    END SELECT
  END DO

  !- read and count types
  nAuxBCplanes    = 0
  nAuxBCcylinders = 0
  nAuxBCcones     = 0
  nAuxBCparabols  = 0

  DO iAuxBC=1,nAuxBCs
    WRITE(UNIT=tmpStr,FMT='(I0)') iAuxBC
    AuxBCType(iAuxBC) = TRIM(GETSTR('Part-AuxBC'//TRIM(tmpStr)//'-Type','plane'))

    SELECT CASE (TRIM(AuxBCType(iAuxBC)))

    CASE ('plane')
      nAuxBCplanes     = nAuxBCplanes + 1
      AuxBCMap(iAuxBC) = nAuxBCplanes

    CASE ('cylinder')
      nAuxBCcylinders  = nAuxBCcylinders + 1
      AuxBCMap(iAuxBC) = nAuxBCcylinders

    CASE ('cone')
      nAuxBCcones      = nAuxBCcones + 1
      AuxBCMap(iAuxBC) = nAuxBCcones

    CASE ('parabol')
      nAuxBCparabols   = nAuxBCparabols + 1
      AuxBCMap(iAuxBC) = nAuxBCparabols

    CASE DEFAULT
      SWRITE(*,*) ' AuxBC does not exist: ', TRIM(AuxBCType(iAuxBC))
      CALL abort(__STAMP__,'AuxBC does not exist')
    END SELECT
  END DO

  !- allocate type-specifics
  IF (nAuxBCplanes.GT.0) THEN
    ALLOCATE (AuxBC_plane(   1:nAuxBCplanes))
  END IF

  IF (nAuxBCcylinders.GT.0) THEN
    ALLOCATE (AuxBC_cylinder(1:nAuxBCcylinders))
  END IF

  IF (nAuxBCcones.GT.0) THEN
    ALLOCATE (AuxBC_cone(    1:nAuxBCcones))
  END IF

  IF (nAuxBCparabols.GT.0) THEN
    ALLOCATE (AuxBC_parabol( 1:nAuxBCparabols))
  END IF

  !- read type-specifics
  DO iAuxBC=1,nAuxBCs
    WRITE(UNIT=tmpStr,FMT='(I0)') iAuxBC
    SELECT CASE (TRIM(AuxBCType(iAuxBC)))

    CASE ('plane')
      AuxBC_plane(AuxBCMap(iAuxBC))%r_vec = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-r_vec',3,'0. , 0. , 0.')
      WRITE(UNIT=tmpStr2,FMT='(G0)') HUGE(AuxBC_plane(AuxBCMap(iAuxBC))%radius)
      AuxBC_plane(AuxBCMap(iAuxBC))%radius= GETREAL(     'Part-AuxBC'//TRIM(tmpStr)//'-radius',TRIM(tmpStr2))
      n_vec                               = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-n_vec',3,'1. , 0. , 0.')
      ! Check if normal vector is zero
      IF (DOT_PRODUCT(n_vec,n_vec).EQ.0.) THEN
        CALL abort(__STAMP__,'Part-AuxBC-n_vec is zero for AuxBC',iAuxBC)
      ! If not, scale vector
      ELSE
        AuxBC_plane(AuxBCMap(iAuxBC))%n_vec = n_vec/SQRT(DOT_PRODUCT(n_vec,n_vec))
      END IF

    CASE ('cylinder')
      AuxBC_cylinder(AuxBCMap(iAuxBC))%r_vec = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-r_vec',3,'0. , 0. , 0.')
      n_vec                                  = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-axis',3,'1. , 0. , 0.')
      ! Check if normal vector is zero
      IF (DOT_PRODUCT(n_vec,n_vec).EQ.0.) THEN
        CALL abort(__STAMP__,'Part-AuxBC-axis is zero for AuxBC',iAuxBC)
      ! If not, scale vector
      ELSE
        AuxBC_cylinder(AuxBCMap(iAuxBC))%axis = n_vec/SQRT(DOT_PRODUCT(n_vec,n_vec))
      END IF

      AuxBC_cylinder(AuxBCMap(iAuxBC))%radius  = GETREAL(   'Part-AuxBC'//TRIM(tmpStr)//'-radius','1.')
      WRITE(UNIT=tmpStr2,FMT='(G0)') -HUGE(AuxBC_cylinder(AuxBCMap(iAuxBC))%lmin)
      AuxBC_cylinder(AuxBCMap(iAuxBC))%lmin    = GETREAL(   'Part-AuxBC'//TRIM(tmpStr)//'-lmin',TRIM(tmpStr2))
      WRITE(UNIT=tmpStr2,FMT='(G0)') HUGE(AuxBC_cylinder(AuxBCMap(iAuxBC))%lmin)
      AuxBC_cylinder(AuxBCMap(iAuxBC))%lmax    = GETREAL(   'Part-AuxBC'//TRIM(tmpStr)//'-lmax',TRIM(tmpStr2))
      AuxBC_cylinder(AuxBCMap(iAuxBC))%inwards = GETLOGICAL('Part-AuxBC'//TRIM(tmpStr)//'-inwards','.TRUE.')

    CASE ('cone')
      AuxBC_cone(AuxBCMap(iAuxBC))%r_vec     = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-r_vec',3,'0. , 0. , 0.')
      n_vec                                  = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-axis',3,'1. , 0. , 0.')
      ! Check if normal vector is zero
      IF (DOT_PRODUCT(n_vec,n_vec).EQ.0.) THEN
        CALL abort(__STAMP__,'Part-AuxBC-axis is zero for AuxBC',iAuxBC)
      ! If not, scale vector
      ELSE
        AuxBC_cone(AuxBCMap(iAuxBC))%axis = n_vec/SQRT(DOT_PRODUCT(n_vec,n_vec))
      END IF

      AuxBC_cone(AuxBCMap(iAuxBC))%lmin  = GETREAL('Part-AuxBC'//TRIM(tmpStr)//'-lmin','0.')
      IF (AuxBC_cone(AuxBCMap(iAuxBC))%lmin.LT.0.) &
        CALL abort(__STAMP__,'Part-AuxBC-lminis .lt. zero for AuxBC',iAuxBC)

      WRITE(UNIT=tmpStr2,FMT='(G0)') HUGE(AuxBC_cone(AuxBCMap(iAuxBC))%lmin)
      AuxBC_cone(AuxBCMap(iAuxBC))%lmax  = GETREAL('Part-AuxBC'//TRIM(tmpStr)//'-lmax',TRIM(tmpStr2))
      rmax                               = GETREAL('Part-AuxBC'//TRIM(tmpStr)//'-rmax','0.')

      ! either define rmax at lmax or the halfangle
      IF (rmax.EQ.0.) THEN
        AuxBC_cone(AuxBCMap(iAuxBC))%halfangle  = GETREAL('Part-AuxBC'//TRIM(tmpStr)//'-halfangle','45.')*PI/180.
      ELSE
        AuxBC_cone(AuxBCMap(iAuxBC))%halfangle  = ATAN(rmax/AuxBC_cone(AuxBCMap(iAuxBC))%lmax)
      END IF

      IF (AuxBC_cone(AuxBCMap(iAuxBC))%halfangle.LE.0.) &
        CALL abort(__STAMP__,'Part-AuxBC-halfangle is .le. zero for AuxBC',iAuxBC)

      AuxBC_cone(AuxBCMap(iAuxBC))%inwards = GETLOGICAL('Part-AuxBC'//TRIM(tmpStr)//'-inwards','.TRUE.')
      cos2 = COS(AuxBC_cone(AuxBCMap(iAuxBC))%halfangle)**2
      AuxBC_cone(AuxBCMap(iAuxBC))%geomatrix(:,1) &
        = AuxBC_cone(AuxBCMap(iAuxBC))%axis(1)*AuxBC_cone(AuxBCMap(iAuxBC))%axis - (/cos2,0.,0./)
      AuxBC_cone(AuxBCMap(iAuxBC))%geomatrix(:,2) &
        = AuxBC_cone(AuxBCMap(iAuxBC))%axis(2)*AuxBC_cone(AuxBCMap(iAuxBC))%axis - (/0.,cos2,0./)
      AuxBC_cone(AuxBCMap(iAuxBC))%geomatrix(:,3) &
        = AuxBC_cone(AuxBCMap(iAuxBC))%axis(3)*AuxBC_cone(AuxBCMap(iAuxBC))%axis - (/0.,0.,cos2/)

    CASE ('parabol')
      AuxBC_parabol(AuxBCMap(iAuxBC))%r_vec = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-r_vec',3,'0. , 0. , 0.')
      n_vec                                 = GETREALARRAY('Part-AuxBC'//TRIM(tmpStr)//'-axis',3,'1. , 0. , 0.')
      ! Check if normal vector is zero
      IF (DOT_PRODUCT(n_vec,n_vec).EQ.0.) THEN
        CALL abort(__STAMP__,'Part-AuxBC-axis is zero for AuxBC',iAuxBC)
      ! If not, scale vector
      ELSE
        AuxBC_parabol(AuxBCMap(iAuxBC))%axis = n_vec/SQRT(DOT_PRODUCT(n_vec,n_vec))
      END IF

      AuxBC_parabol(AuxBCMap(iAuxBC))%lmin  = GETREAL(     'Part-AuxBC'//TRIM(tmpStr)//'-lmin','0.')
      IF (AuxBC_parabol(AuxBCMap(iAuxBC))%lmin.LT.0.) &
        CALL abort(__STAMP__,'Part-AuxBC-lmin is .lt. zero for AuxBC',iAuxBC)

      WRITE(UNIT=tmpStr2,FMT='(G0)') HUGE(AuxBC_parabol(AuxBCMap(iAuxBC))%lmin)
      AuxBC_parabol(AuxBCMap(iAuxBC))%lmax  = GETREAL(     'Part-AuxBC'//TRIM(tmpStr)//'-lmax',TRIM(tmpStr2))
      AuxBC_parabol(AuxBCMap(iAuxBC))%zfac  = GETREAL(     'Part-AuxBC'//TRIM(tmpStr)//'-zfac','1.')
      AuxBC_parabol(AuxBCMap(iAuxBC))%inwards = GETLOGICAL('Part-AuxBC'//TRIM(tmpStr)//'-inwards','.TRUE.')

      n(:,1)=AuxBC_parabol(AuxBCMap(iAuxBC))%axis

      ! Check if normal vector is colliniar with y?
      IF (.NOT.ALMOSTZERO(SQRT(n(1,1)**2+n(3,1)**2))) THEN
        alpha1 = ATAN2(n(1,1),n(3,1))
        CALL roty(rot1,alpha1)
        n1     = MATMUL(rot1,n)
      ELSE
        alpha1 = 0.
        CALL ident(rot1)
        n1     = n
      END IF

      ! Check if normal vector is colliniar with x?
      IF (.NOT.ALMOSTZERO(SQRT(n1(2,1)**2+n1(3,1)**2))) THEN
        alpha2 = -ATAN2(n1(2,1),n1(3,1))
        CALL rotx(rot2,alpha2)
        n2     = MATMUL(rot2,n1)
      ELSE
        CALL abort(__STAMP__,'Vector is collinear with x-axis. this should not be possible... AuxBC:',iAuxBC)
      END IF

      AuxBC_parabol(AuxBCMap(iAuxBC))%rotmatrix(:,:)  = MATMUL(rot2,rot1)
      AuxBC_parabol(AuxBCMap(iAuxBC))%geomatrix4(:,:) = 0.
      AuxBC_parabol(AuxBCMap(iAuxBC))%geomatrix4(1,1) = 1.
      AuxBC_parabol(AuxBCMap(iAuxBC))%geomatrix4(2,2) = 1.
      AuxBC_parabol(AuxBCMap(iAuxBC))%geomatrix4(3,3) = 0.
      AuxBC_parabol(AuxBCMap(iAuxBC))%geomatrix4(3,4) = -0.5*AuxBC_parabol(AuxBCMap(iAuxBC))%zfac
      AuxBC_parabol(AuxBCMap(iAuxBC))%geomatrix4(4,3) = -0.5*AuxBC_parabol(AuxBCMap(iAuxBC))%zfac

    CASE DEFAULT
      SWRITE(*,*) ' AuxBC does not exist: ', TRIM(AuxBCType(iAuxBC))
      CALL abort(__STAMP__,'AuxBC does not exist for AuxBC',iAuxBC)

    END SELECT
  END DO

  ! Mark elements with auxiliary BCs
  CALL MarkAuxBCElems()
ELSE
  ! Flag if AuxBCs are used
  UseAuxBCs=.FALSE.
END IF

END SUBROUTINE InitializeVariablesAuxBC


!SUBROUTINE InitializeVariablesTimeStep(ManualTimeStep_opt)
SUBROUTINE InitializeVariablesTimeStep()
!===================================================================================================================================
! Initialize the variables first
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_ReadInTools
USE MOD_Particle_Vars
!USE MOD_Particle_Timedisc_Vars,   ONLY: useManualTimeStep,ManualTimeStep
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!REAL,INTENT(IN),OPTIONAL   :: ManualTimeStep_opt
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
!!--- Read Manual Time Step
!useManualTimeStep = .FALSE.
!!> ManualTimeStep_opt only gets passed when running Posti. InitTimedisc was not called, so get information here
!IF (.NOT.PRESENT(ManualTimeStep_opt)) ManualTimeStep    = GETREAL('Part-ManualTimeStep', '0.0')
!IF (ManualTimeStep.GT.0.0)            useManualTimeStep = .TRUE.

! Time delay before initial particle inserting
DelayTime         = GETREAL(   'Part-DelayTime'    ,'0.')

END SUBROUTINE InitializeVariablesTimeStep



!===================================================================================================================================
! finalize particle variables
!===================================================================================================================================
SUBROUTINE FinalizeParticles()
! MODULES
USE MOD_Globals
USE MOD_ErosionPoints,              ONLY: FinalizeErosionPoints
USE MOD_Particle_Analyze,           ONLY: FinalizeParticleAnalyze
USE MOD_Particle_Boundary_Vars
USE MOD_Particle_Boundary_Sampling, ONLY: FinalizeParticleBoundarySampling
USE MOD_Particle_Interpolation,     ONLY: FinalizeParticleInterpolation
USE MOD_Particle_Mesh,              ONLY: FinalizeParticleMesh
USE MOD_Particle_SGS,               ONLY: ParticleFinalizeSGS
USE MOD_Particle_Surfaces,          ONLY: FinalizeParticleSurfaces
USE MOD_Particle_Vars
#if USE_MPI
USE MOD_Particle_MPI_Emission,      ONLY: FinalizeEmissionComm
USE MOD_Particle_MPI_Halo,          ONLY: FinalizePartExchangeProcs
#endif /*USE_MPI*/
#if USE_RW
USE MOD_Particle_RandomWalk,        ONLY: ParticleFinalizeRandomWalk
#endif /*USE_RW*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

#if USE_MPI
! Must be finalized before Species is deallocated
CALL FinalizeEmissionComm
#endif

! particle properties
SDEALLOCATE(Species)
SDEALLOCATE(PartState)
SDEALLOCATE(PartReflCount)
SDEALLOCATE(LastPartPos)
SDEALLOCATE(PartPosRef)
SDEALLOCATE(PartSpecies)
SDEALLOCATE(PartIndex)

! Runge-Kutta time stepping
SDEALLOCATE(Pt)
SDEALLOCATE(Pt_temp)

! particle position in reference coordinates
SDEALLOCATE(PDM%ParticleInside)
SDEALLOCATE(PDM%nextFreePosition)
SDEALLOCATE(PDM%nextFreePosition)
SDEALLOCATE(PDM%IsNewPart)

! particle boundary information
SDEALLOCATE(PartBound%SourceBoundName)
SDEALLOCATE(PartBound%SourceBoundType)
SDEALLOCATE(PartBound%TargetBoundCond)
SDEALLOCATE(PartBound%WallTemp)
SDEALLOCATE(PartBound%WallVelo)
!SDEALLOCATE(PartBound%AmbientCondition)
!SDEALLOCATE(PartBound%AmbientConditionFix)
!SDEALLOCATE(PartBound%AmbientTemp)
!SDEALLOCATE(PartBound%AmbientVelo)
!SDEALLOCATE(PartBound%AmbientDens)
!SDEALLOCATE(PartBound%AmbientDynamicVisc)
SDEALLOCATE(PartBound%WallModel)
SDEALLOCATE(PartBound%WallCoeffModel)
SDEALLOCATE(PartBound%Young)
SDEALLOCATE(PartBound%Poisson)
SDEALLOCATE(PartBound%CoR)

! particle-to-element-mapping (PEM) arrays
SDEALLOCATE(PEM%Element)
SDEALLOCATE(PEM%lastElement)
SDEALLOCATE(PEM%pStart)
SDEALLOCATE(PEM%pNumber)
SDEALLOCATE(PEM%pEnd)
SDEALLOCATE(PEM%pNext)

! interpolation
CALL FinalizeParticleInterpolation

! random walk
#if USE_RW
CALL ParticleFinalizeRandomWalk()
#endif /*USE_RW*/

!
SDEALLOCATE(Seeds)

! subgrid-scale model
CALL ParticleFinalizeSGS()

! particle impact tracking
CALL FinalizeErosionPoints()

! particle surface sampling
CALL FinalizeParticleBoundarySampling()

#if USE_MPI
! particle MPI halo exchange
CALL FinalizePartExchangeProcs()
#endif

CALL FinalizeParticleAnalyze()
CALL FinalizeParticleSurfaces()
CALL FinalizeParticleMesh()

ParticlesInitIsDone = .FALSE.

END SUBROUTINE FinalizeParticles


!===================================================================================================================================
SUBROUTINE rotx(mat,a)
! MODULES                                                                                                                          !
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL, INTENT(OUT), DIMENSION(3,3) :: mat
REAL, INTENT(IN)                  :: a
!===================================================================================================================================
mat(:,1)=(/1.0 , 0.     , 0.  /)
mat(:,2)=(/0.0 , COS(a) ,-SIN(a)/)
mat(:,3)=(/0.0 , SIN(a) , COS(a)/)
END SUBROUTINE


!===================================================================================================================================
SUBROUTINE roty(mat,a)
! MODULES                                                                                                                          !
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL, INTENT(OUT), DIMENSION(3,3) :: mat
REAL, INTENT(IN)                  :: a
!===================================================================================================================================
mat(:,1)=(/ COS(a) , 0., SIN(a)/)
mat(:,2)=(/ 0.     , 1., 0.  /)
mat(:,3)=(/-SIN(a) , 0., COS(a)/)
END SUBROUTINE


!===================================================================================================================================
SUBROUTINE ident(mat)
! MODULES                                                                                                                          !
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL, INTENT(OUT), DIMENSION(3,3) :: mat
INTEGER                           :: j
!===================================================================================================================================

mat                      = 0.
FORALL(j = 1:3) mat(j,j) = 1.
END SUBROUTINE


SUBROUTINE InitRandomSeed(nRandomSeeds,SeedSize,Seeds)
!===================================================================================================================================
!> Initialize pseudo random numbers: Create Random_seed array
!===================================================================================================================================
! MODULES
#if USE_MPI
USE MOD_Particle_MPI_Vars,     ONLY:PartMPI
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)             :: nRandomSeeds
INTEGER,INTENT(IN)             :: SeedSize
INTEGER,INTENT(INOUT)          :: Seeds(SeedSize)
!----------------------------------------------------------------------------------------------------------------------------------!
! LOCAL VARIABLES
INTEGER                        :: iSeed,DateTime(8),ProcessID,iStat,OpenFileID,GoodSeeds
INTEGER(KIND=8)                :: Clock,AuxilaryClock
LOGICAL                        :: uRandomExists
!==================================================================================================================================

uRandomExists=.FALSE.
IF (nRandomSeeds.NE.-1) THEN
  Clock     = 1536679165842_8
  ProcessID = 3671
ELSE
! First try if the OS provides a random number generator
  OPEN(NEWUNIT=OpenFileID, FILE="/dev/urandom", ACCESS="stream", &
       FORM="unformatted", ACTION="read", STATUS="old", IOSTAT=iStat)
  IF (iStat.EQ.0) THEN
    READ(OpenFileID) Seeds
    CLOSE(OpenFileID)
    uRandomExists=.TRUE.
  ELSE
    ! Fallback to XOR:ing the current time and pid. The PID is
    ! useful in case one launches multiple instances of the same
    ! program in parallel.
    CALL SYSTEM_CLOCK(COUNT=Clock)
    IF (Clock .EQ. 0) THEN
      CALL DATE_AND_TIME(values=DateTime)
      Clock =(DateTime(1) - 1970) * 365_8 * 24 * 60 * 60 * 1000 &
      + DateTime(2) * 31_8 * 24 * 60 * 60 * 1000 &
      + DateTime(3) * 24_8 * 60 * 60 * 1000 &
      + DateTime(5) * 60 * 60 * 1000 &
      + DateTime(6) * 60 * 1000 &
      + DateTime(7) * 1000 &
      + DateTime(8)
    END IF
    ProcessID = GetPID_C()
  END IF
END IF
IF(.NOT. uRandomExists) THEN
  Clock = IEOR(Clock, INT(ProcessID, KIND(Clock)))
  AuxilaryClock=Clock
  DO iSeed = 1, SeedSize
#if USE_MPI
    IF (nRandomSeeds.EQ.0) THEN
      AuxilaryClock=AuxilaryClock+PartMPI%MyRank
    ELSE IF(nRandomSeeds.GT.0) THEN
      AuxilaryClock=AuxilaryClock+(PartMPI%MyRank+1)*Seeds(iSeed)*37
    END IF
#else
    IF (nRandomSeeds.GT.0) THEN
      AuxilaryClock=AuxilaryClock+Seeds(iSeed)*37
    END IF
#endif
    IF (AuxilaryClock .EQ. 0) THEN
      AuxilaryClock = 104729
    ELSE
      AuxilaryClock = MOD(AuxilaryClock, 4294967296_8)
    END IF
    AuxilaryClock = MOD(AuxilaryClock * 279470273_8, 4294967291_8)
    GoodSeeds = INT(MOD(AuxilaryClock, INT(HUGE(0),KIND=8)), KIND(0))
    Seeds(iSeed) = GoodSeeds
  END DO
END IF
CALL RANDOM_SEED(PUT=Seeds)

END SUBROUTINE InitRandomSeed

END MODULE MOD_Particle_Init
