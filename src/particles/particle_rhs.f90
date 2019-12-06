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
! Subroutine to compute the particle right hand side, therefore the acceleration due to the Lorentz-force with
! respect to the Lorentz factor
!===================================================================================================================================
MODULE MOD_part_RHS
! MODULES
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------

INTERFACE CalcPartRHS
  MODULE PROCEDURE CalcPartRHS
END INTERFACE

PUBLIC :: CalcPartRHS
!==================================================================================================================================

CONTAINS

SUBROUTINE CalcPartRHS()
!===================================================================================================================================
! Computes the acceleration from the drag force with respect to the species data and velocity
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Globals
USE MOD_Particle_Interpolation_Vars,  ONLY: FieldAtParticle
USE MOD_Particle_Vars,                ONLY: PDM, Pt
!#if USE_RW
!USE MOD_Particle_RandomWalk_Vars,     ONLY: RWTime
!USE MOD_Particle_Vars,                ONLY: Species,PartSpecies,TurbPartState
!USE MOD_TimeDisc_Vars,                ONLY: t
!#endif
!----------------------------------------------------------------------------------------------------------------------------------
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLE
INTEGER                          :: iPart
!===================================================================================================================================

! Drag force
Pt(:,1:PDM%ParticleVecLength)=0.

DO iPart = 1,PDM%ParticleVecLength
  IF (PDM%ParticleInside(iPart)) THEN
!#if USE_RW
!    ! Do not change the particle velocity if RW is working in full Euler mode
!    !> Ideally, this should use tStage. But one cannot start a RK without the first stage and it does not make a difference for Euler
!    IF (RWTime.EQ.'RW') .AND. (t.LT.TurbPartState(4,iPart))) CYCLE
!#endif
    Pt(1:3,iPart) = ParticlePush(iPart,FieldAtParticle(1:PP_nVar,iPart))
  END IF
END DO

END SUBROUTINE CalcPartRHS

FUNCTION ParticlePush(PartID,FieldAtParticle)
!===================================================================================================================================
! Push due to Stoke's drag and source terms (gravity)
!===================================================================================================================================
! MODULES
USE MOD_Particle_Globals
USE MOD_Particle_Vars,     ONLY : Species, PartSpecies, PartGravity
USE MOD_Particle_Vars,     ONLY : PartState, RepWarn
USE MOD_EOS_Vars,          ONLY : mu0
#if USE_RW
USE MOD_Particle_Vars,     ONLY : TurbPartState
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)  :: PartID
REAL,INTENT(IN)     :: FieldAtParticle(1:PP_nVar)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL                :: ParticlePush(1:3) ! The stamp
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                :: Pt(1:3)
REAL                :: Rep                        ! Reynolds number of particle
!REAL                :: velosqp                    ! v^2 particle
!REAL                :: velosqf                    ! v^2 fluid
REAL                :: udiff(3)
REAL                :: Vol,r
REAL                :: Cd
REAL                :: Fd(1:3)
REAL                :: Fstokes(1:3)
REAL                :: taup
REAL                :: nu
!===================================================================================================================================

SELECT CASE(TRIM(Species(PartSpecies(PartID))%RHSMethod))

CASE('None')
!===================================================================================================================================
! Debug RHS method for purely inertial particle movement
!===================================================================================================================================
Pt = 0

CASE('Tracer')
!===================================================================================================================================
! Passive tracer moving with fluid velocity
!===================================================================================================================================
Pt      = FieldAtParticle(2:4)/FieldAtParticle(1)

CASE('Convergence')
!===================================================================================================================================
! Special case, drag force only active in x-direction, fixed differential. Gravity in y-direction. Used for convergence tests
!===================================================================================================================================
udiff(1)   = PartState(4,PartID) - (FieldAtParticle(2)/FieldAtParticle(1))
udiff(2:3) = 0.
Pt(1)      = - udiff(1)

! Gravity fixed to -3
Pt(2)      = -3.
Pt(3)      = 0.

CASE('Wang')
!===================================================================================================================================
! Calculation according to Wang [1996]
!===================================================================================================================================
IF(ISNAN(mu0) .OR. (mu0.EQ.0)) CALL abort(&
  __STAMP__&
  ,'Particle tracking with Wang [1996] requires mu0 to be set!')

! Assume spherical particles for now
Vol     = Species(PartSpecies(PartID))%MassIC/Species(PartSpecies(PartID))%DensityIC
r       = (3.*Vol/4./pi)**(1./3.)

#if USE_RW
udiff(1:3) = PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID))
#else
udiff(1:3) = PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1))
#endif

Rep     = SQRT(SUM(udiff(1:3)**2.))*(2.*r)/(mu0/FieldAtParticle(1))
Cd      = 24./Rep*(1. + 0.15*Rep**0.687)

! Warn when outside valid range of Wang model
IF(Rep.GT.40) THEN
  IF (RepWarn.EQV..FALSE.) THEN
    SWRITE(UNIT_StdOut,*) 'WARNING: Rep',Rep,'> 40, Wang method may not be accurate.'
    RepWarn=.TRUE.
  ENDIF
ENDIF

#if USE_RW
Pt      = - FieldAtParticle(1)/Species(PartSpecies(PartID))%DensityIC * 3./4. * Cd/(2.*r) * SQRT(SUM(udiff(1:3)**2)) &
          * (PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID)))
#else
Pt      = - FieldAtParticle(1)/Species(PartSpecies(PartID))%DensityIC * 3./4. * Cd/(2.*r) * SQRT(SUM(udiff(1:3)**2)) &
          * (PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1)))
#endif

! Add gravity if required
IF(ANY(PartGravity.NE.0)) THEN
    Pt  = Pt + PartGravity
ENDIF

CASE('Vinkovic')
!===================================================================================================================================
! Calculation according to Vinkovic [2006]
!===================================================================================================================================
IF(ISNAN(mu0) .OR. (mu0.EQ.0)) CALL abort(&
  __STAMP__&
  ,'Particle tracking with Vinkovic [2006] requires mu0 to be set!')

! Assume spherical particles for now
Vol     = Species(PartSpecies(PartID))%MassIC/Species(PartSpecies(PartID))%DensityIC
r       = (3.*Vol/4./pi)**(1./3.)

! Get nu to stay in same equation format
nu      = mu0/FieldAtParticle(1)

#if USE_RW
udiff(1:3) = PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID))
#else
udiff(1:3) = PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1))
#endif
Rep     = 2.*r*SQRT(SUM(udiff(1:3)**2))/nu

! Empirical relation of nonlinear drag from Clift et al. (1978)
IF (Rep .LT. 1) THEN
    Cd  = 1.
ELSE
    Cd  = 1. + 0.15*Rep**0.687
ENDIF

taup    = (Species(PartSpecies(PartID))%DensityIC*(2.*r)**2.)/(18*FieldAtParticle(1)*nu)

#if USE_RW
Pt      = ((FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID)) - PartState(4:6,PartID))/taup * Cd
#else
Pt      =  (FieldAtParticle(2:4)/FieldAtParticle(1)                              - PartState(4:6,PartID))/taup * Cd
#endif

! Add gravity if required
IF(ANY(PartGravity.NE.0)) THEN
    Pt  = Pt + PartGravity
ENDIF

CASE('Jacobs')
!===================================================================================================================================
! Calculation according to Jacobs [2003]
!===================================================================================================================================
IF(ISNAN(mu0) .OR. (mu0.EQ.0)) CALL abort(&
  __STAMP__&
  ,'Particle tracking with Jacobs [2003] requires mu0 to be set!')

! Assume spherical particles for now
Vol     = Species(PartSpecies(PartID))%MassIC/Species(PartSpecies(PartID))%DensityIC
r       = (3.*Vol/4./pi)**(1./3.)

#if USE_RW
udiff(1:3) = PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID))
#else
udiff(1:3) = PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1))
#endif
Rep     = 2.*FieldAtParticle(1)*r*SQRT(SUM(udiff(1:3)**2.))
Cd      = 1. + (Rep**2./3.)/6.

IF(Rep.LT.1) THEN
#if USE_RW
    Fstokes = 6.   *pi*mu0*r*((FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID)) - PartState(4:6,PartID))
#else
    Fstokes = 6.   *pi*mu0*r*((FieldAtParticle(2:4)/FieldAtParticle(1)                            ) - PartState(4:6,PartID))
#endif
ELSE
#if USE_RW
    Fstokes = 6.*Cd*pi*mu0*r*((FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID)) - PartState(4:6,PartID))
#else
    Fstokes = 6.*Cd*pi*mu0*r*((FieldAtParticle(2:4)/FieldAtParticle(1)                            ) - PartState(4:6,PartID))
#endif

    IF(Rep.GT.1000) THEN
      IF (RepWarn.EQV..FALSE.) THEN
        SWRITE(UNIT_StdOut,*) 'WARNING: Red',Rep,'> 1000, Jacobs method may not be accurate. Please use Jacobs-highRe tracking.'
        RepWarn=.TRUE.
      ENDIF
    END IF
END IF

! Add gravity if required
IF(ANY(PartGravity.NE.0)) THEN
    Fd  = Fstokes + Species(PartSpecies(PartID))%MassIC * PartGravity
ELSE
    Fd  = Fstokes
ENDIF

Pt      = Fd/Species(PartSpecies(PartID))%MassIC

CASE('Jacobs-highRe')
!===================================================================================================================================
! Calculation according to Jacobs [2003]
!===================================================================================================================================
IF(ISNAN(mu0) .OR. (mu0.EQ.0)) CALL abort(&
  __STAMP__&
  ,'Particle tracking with Jacobs [2003] requires mu0 to be set!')

! Assume spherical particles for now
Vol     = Species(PartSpecies(PartID))%MassIC/Species(PartSpecies(PartID))%DensityIC
r       = (3.*Vol/4./pi)**(1./3.)

#if USE_RW
udiff(1:3) = PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID))
#else
udiff(1:3) = PartState(4:6,PartID) - (FieldAtParticle(2:4)/FieldAtParticle(1))
#endif
Rep     = 2.*FieldAtParticle(1)*r*SQRT(SUM(udiff(1:3)**2.))
Cd      = 1. + (Rep**2./3.)/6.

#if USE_RW
Fstokes = .5*FieldAtParticle(1) * Cd * pi * r**2. * ((FieldAtParticle(2:4)/FieldAtParticle(1) + TurbPartState(1:3,PartID)) &
                                                                                               - PartState(4:6,PartID)) * SQRT(SUM(udiff(1:3)**2.))
#else
Fstokes = .5*FieldAtParticle(1) * Cd * pi * r**2. * ((FieldAtParticle(2:4)/FieldAtParticle(1)) - PartState(4:6,PartID)) * SQRT(SUM(udiff(1:3)**2.))
#endif

! Add gravity if required
IF(ANY(PartGravity.NE.0)) THEN
    Fd  = Fstokes + Species(PartSpecies(PartID))%MassIC * PartGravity
ELSE
    Fd  = Fstokes
ENDIF

Pt      = Fd/Species(PartSpecies(PartID))%MassIC

CASE DEFAULT
  CALL abort(&
  __STAMP__&
  ,'No valid RHS method given.')

END SELECT

ParticlePush = Pt

END FUNCTION ParticlePush

END MODULE MOD_part_RHS
