!==========================================================================================!
!==========================================================================================!
!                                                                                          !
!     This subroutine computes the characteristic scales, using one of the following surf- !
! ace layer parametrisation.                                                               !
!                                                                                          !
!                                                                                          !
! 1. Based on L79;                                                                         !
! 2. Based on: OD95, but with some terms computed as in L79 and B71 to avoid singular-     !
!    ities (now using the iterative method to find zeta).                                  !
! 3. Based on BH91, using an iterative method to find zeta, and using the modified         !
!    equation for stable layers.                                                           !
! 4. Based on CLM04, with special functions for very stable and very stable case, even     !
!    though we use a different functional form for very unstable case for momentum.        !
!    This is ensure that phi_m decreases monotonically as zeta becomes more negative.      !
!    We use a power law of order of -1/6 instead.                                          !
!                                                                                          !
! References:                                                                              !
! B71.  BUSINGER, J.A, et. al; Flux-Profile relationships in the atmospheric surface       !
!           layer. J. Atmos. Sci., 28, 181-189, 1971.                                      !
! L79.  LOUIS, J.F.; Parametric Model of vertical eddy fluxes in the atmosphere.           !
!           Boundary-Layer Meteor., 17, 187-202, 1979.                                     !
! BH91. BELJAARS, A.C.M.; HOLTSLAG, A.A.M.; Flux parameterization over land surfaces for   !
!           atmospheric models. J. Appl. Meteor., 30, 327-341, 1991.                       !
! OD95. ONCLEY, S.P.; DUDHIA, J.; Evaluation of surface fluxes from MM5 using observa-     !
!           tions.  Mon. Wea. Rev., 123, 3344-3357, 1995.                                  !
! CLM04. OLESON, K. W., et al.; Technical description of the community land model (CLM)    !
!           NCAR Technical Note NCAR/TN-461+STR, Boulder, CO, May 2004.                    !
!                                                                                          !
!------------------------------------------------------------------------------------------!
subroutine leaf3_stars(theta_atm,enthalpy_atm,shv_atm,rvap_atm,co2_atm                     &
                      ,theta_can,enthalpy_can,shv_can,rvap_can,co2_can                     &
                      ,zref,dheight,uref,dtll,rough,ustar,tstar,estar,qstar,rstar,cstar    &
                      ,zeta,rib,r_aer)
   use mem_leaf  , only : istar      ! ! intent(in)
   use rconstants, only : grav       & ! intent(in)
                        , vonk       & ! intent(in)
                        , epim1      & ! intent(in)
                        , halfpi     ! ! intent(in)
   use leaf_coms , only : ustmin     & ! intent(in)
                        , bl79       & ! intent(in)
                        , csm        & ! intent(in)
                        , csh        & ! intent(in)
                        , dl79       & ! intent(in)
                        , ribmax     & ! intent(in)
                        , tprandtl   & ! intent(in)
                        , z0moz0h    & ! intent(in)
                        , z0hoz0m    & ! intent(in)
                        , ggbare     & ! intent(out)
                        , psim       & ! function
                        , psih       & ! function
                        , zoobukhov  ! ! function
   use node_mod  , only : mynum      ! ! intent(in)
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   real, intent(in)  :: theta_atm    ! Above canopy air pot. temperature        [        K]
   real, intent(in)  :: enthalpy_atm ! Above canopy air specific enthalpy       [     J/kg]
   real, intent(in)  :: shv_atm      ! Above canopy vapour spec. hum.           [kg/kg_air]
   real, intent(in)  :: rvap_atm     ! Above canopy vapour mixing ratio         [kg/kg_air]
   real, intent(in)  :: co2_atm      ! Above canopy CO2 mixing ratio            [ �mol/mol]
   real, intent(in)  :: theta_can    ! Canopy air potential temperature         [        K]
   real, intent(in)  :: enthalpy_can ! Canopy air specific enthalpy             [     J/kg]
   real, intent(in)  :: shv_can      ! Canopy air vapour spec. humidity         [kg/kg_air]
   real, intent(in)  :: rvap_can     ! Canopy air vapour mixing ratio           [kg/kg_air]
   real, intent(in)  :: co2_can      ! Canopy air CO2 mixing ratio              [ �mol/mol]
   real, intent(in)  :: zref         ! Height at reference point                [        m]
   real, intent(in)  :: dheight      ! Displacement height                      [        m]
   real, intent(in)  :: uref         ! Wind speed at reference height           [      m/s]
   real, intent(in)  :: dtll         ! Time step                                [        m]
   real, intent(in)  :: rough        ! z0, the roughness                        [        m]
   real, intent(out) :: ustar        ! U*, friction velocity                    [      m/s]
   real, intent(out) :: tstar        ! Temperature friction scale               [        K]
   real, intent(out) :: estar        ! Theta_Eiv friction scale                 [        K]
   real, intent(out) :: qstar        ! Specific humidity friction scale         [kg/kg_air]
   real, intent(out) :: rstar        ! Vapour mixing ratio friction scale       [kg/kg_air]
   real, intent(out) :: cstar        ! CO2 mixing ratio                         [ �mol/mol]
   real, intent(out) :: zeta         ! z/(Obukhov length).                      [      ---]
   real, intent(out) :: rib          ! Bulk richardson number.                  [      ---]
   real, intent(out) :: r_aer        ! Aerodynamic resistance                   [      s/m]
   !----- Local variables, common to both models. -----------------------------------------!
   logical           :: stable       ! Stable state
   real              :: zoz0m        ! zref/rough(momentum)
   real              :: lnzoz0m      ! ln[zref/rough(momentum)]
   real              :: zoz0h        ! zref/rough(heat)
   real              :: lnzoz0h      ! ln[zref/rough(heat)]
   real              :: c3           ! coefficient to find the other stars
   real              :: delz         !
   real              :: d_vel        !
   real              :: vel_new      !
   real              :: uuse         ! Wind for too stable cases (Rib > Ribmax)
   !----- Local variables, used by L79. ---------------------------------------------------!
   real              :: a2           ! Drag coefficient in neutral conditions
   real              :: c1           ! a2 * vels
   real              :: fh           ! Stability parameter for heat
   real              :: fm           ! Stability parameter for momentum
   real              :: c2           ! Part of the c coefficient common to momentum & heat.
   real              :: cm           ! c coefficient times |Rib|^1/2 for momentum.
   real              :: ch           ! c coefficient times |Rib|^1/2 for heat.
   real              :: ee           ! (z/z0)^1/3 -1. for eqn. 20 w/o assuming z/z0 >> 1.
   !----- Local variables, used by OD95 and/or BH91. --------------------------------------!
   real              :: zeta0m       ! roughness(momentum)/(Obukhov length).
   real              :: zeta0h       ! roughness(heat)/(Obukhov length).
   real              :: utotal       ! Total wind (actual + convective)
   real              :: uconv        ! Convective velocity
   real              :: uconv_prev   ! Previous convective velocity
   real              :: change       ! Difference in convective velocity
   integer           :: icnt         ! Iteration counter
   !----- Aux. environment conditions. ----------------------------------------------------!
   real              :: thetav_atm   ! Atmos. virtual potential temperature     [        K]
   real              :: thetav_can   ! Canopy air virtual pot. temperature      [        K]
   !----- External functions. -------------------------------------------------------------!
   real, external    :: cbrt          ! Cubic root
   real, external    :: leaf3_sflux_w ! Surface flux in the w direction
   !---------------------------------------------------------------------------------------!


   !----- Find the variables common to both methods. --------------------------------------!
   thetav_atm = theta_atm * (1. + epim1 * shv_atm)
   thetav_can = theta_can * (1. + epim1 * shv_can)
   zoz0m      = (zref-dheight)/rough
   lnzoz0m    = log(zoz0m)
   zoz0h      = z0moz0h * zoz0m
   lnzoz0h    = log(zoz0h)
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     Find the Bulk Richardson number.  For stable cases, and for L79 in both cases,    !
   ! this will be the definitive RiB, whilst this is the first guess, which will be        !
   ! corrected by the convective velocity in the other unstable cases.                     !
   !---------------------------------------------------------------------------------------!
   rib        = 2.0 * grav * (zref-dheight-rough) * (thetav_atm-thetav_can)                &
              / ( (thetav_atm+thetav_can) * uref * uref)
   stable     = thetav_atm >= thetav_can
   !---------------------------------------------------------------------------------------!




   !---------------------------------------------------------------------------------------!
   !    Correct the bulk Richardson number in case it's too stable.  We also define a      !
   ! stable case correction to bring down the stars other than ustar, so the flux doesn't  !
   ! increase for stabler cases (it remains constant).                                     !
   !---------------------------------------------------------------------------------------!
   if (rib > ribmax) then
      uuse = sqrt(rib/ribmax) * uref
      rib  = ribmax
   else
      uuse = uref
   end if
   !---------------------------------------------------------------------------------------!




   !---------------------------------------------------------------------------------------!
   !     Here we find u* and the coefficient to find the other stars based on the chosen   !
   ! surface model.                                                                        !
   !---------------------------------------------------------------------------------------!
   select case (istar)
   case (1)
      !------------------------------------------------------------------------------------!
      !     Here we will use L79 model, the BRAMS default.                                 !
      !------------------------------------------------------------------------------------!

      !----- Compute the a-square factor and the coefficient to find theta*. --------------!
      a2   = (vonk / lnzoz0m) ** 2.
      c1   = a2 * uuse

      if (stable) then
         !---------------------------------------------------------------------------------!
         !     Stable case.                                                                !
         !---------------------------------------------------------------------------------!
         fm = 1.0 / (1.0 + (2.0 * bl79 * rib / sqrt(1.0 + dl79 * rib)))
         fh = 1.0 / (1.0 + (3.0 * bl79 * rib * sqrt(1.0 + dl79 * rib)))

      else
         !---------------------------------------------------------------------------------!
         !     Unstable case.  The only difference from the original method is that we no  !
         ! longer assume z >> z0, so the "c" coefficient uses the full z/z0 term.          !
         !---------------------------------------------------------------------------------!
         ee = cbrt(zoz0m) - 1.
         c2 = bl79 * a2 * ee * sqrt(ee * abs(rib))
         cm = csm * c2
         ch = csh * c2
         fm = (1.0 - 2.0 * bl79 * rib / (1.0 + 2.0 * cm))
         fh = (1.0 - 3.0 * bl79 * rib / (1.0 + 3.0 * ch))
      end if
      r_aer = 1. / (a2 * uuse * fh)

      !----- Finding ustar, making sure it is not too small. ------------------------------!
      ustar = max(ustmin,sqrt(c1 * uuse * fm))

      !----- Finding the coefficient to scale the other stars. ----------------------------!
      c3 = c1 * fh / ustar
      !------------------------------------------------------------------------------------!


      !----- Compute zeta from u* and T* --------------------------------------------------!
      zeta = grav * vonk * c3 * (theta_atm - theta_can) / (theta_atm * ustar * ustar)
      !------------------------------------------------------------------------------------!


   case default
      !------------------------------------------------------------------------------------!
      ! 2. Here we use the model proposed by OD95, the standard for MM5, but with some     !
      !    terms that were computed in B71 (namely, the "0" terms), which prevent sin-     !
      !    gularities.                                                                     !
      !    However we know zeta, so zeta0 can be written as z0/z * zeta.                   !
      ! 3. Here we use the model proposed by BH91, which is almost the same as the OD95    !
      !    method, except that the stable functions are computed in a more generic way.    !
      !    BH91 claim that the oft-used approximation (-beta*zeta) can cause poor          !
      !    ventilation of the stable layer, leading to decoupling between the atmo-        !
      !    sphere and the canopy air space and excessive cooling                           !
      ! 4. Here we use a similar approach as in CLM04, excepth that the momentum flux      !
      !    gradient function for the unstable case for momentum is switched by a power     !
      !    of -1/6 (kind of the square of the heat one).  This is to guarantee that        !
      !    the psi function doesn't have local maxima/minima.                              !
      !------------------------------------------------------------------------------------!
      !----- Initialise uconv. ------------------------------------------------------------!
      uconv      = 0.0
      !----- Check if we need to go through the iterative process. ------------------------!
      if (stable) then
         !----- We now compute the stability correction functions. ------------------------!
         zeta   = zoobukhov(rib,zref-dheight,rough,zoz0m,lnzoz0m,zoz0h,lnzoz0h,stable)
         zeta0m = rough * zeta / (zref-dheight)
         zeta0h = z0hoz0m * zeta0m

         !----- Find the aerodynamic resistance similarly to L79. -------------------------!
         r_aer = tprandtl * (lnzoz0h - psih(zeta,stable) + psih(zeta0h,stable))            &
                          * (lnzoz0m - psim(zeta,stable) + psim(zeta0m,stable))            &
                          / (vonk * vonk * uuse)

         !----- Find ustar, making sure it is not too small. ------------------------------!
         ustar = max (ustmin, vonk * uuse                                                  &
                            / (lnzoz0m - psim(zeta,stable) + psim(zeta0m,stable)))


         !----- Find the coefficient to scale the other stars. ----------------------------!
         c3    = vonk / (tprandtl * (lnzoz0h - psih(zeta,stable) + psih(zeta0h,stable)))
         !---------------------------------------------------------------------------------!
      else
         !---------------------------------------------------------------------------------!
         !    Unstable case.  Here we run a few iterations to make sure we correct the     !
         ! bulk Richardson number.  This is really a simple correction, so we don't need   !
         ! uconv to be totally in equilibrium.                                             !
         !---------------------------------------------------------------------------------!
         unstable: do icnt=1,6
            !----- Update total winds. ----------------------------------------------------!
            uconv_prev = uconv
            utotal     = sqrt(uuse*uuse + uconv_prev * uconv_prev)
            !------------------------------------------------------------------------------!


            !----- Update the Bulk Richardson number. -------------------------------------!
            rib        = 2.0 * grav * (zref-dheight-rough) * (thetav_atm-thetav_can)       &
                       / ( (thetav_atm+thetav_can) * utotal)
            !------------------------------------------------------------------------------!


            !----- We now compute the stability correction functions. ---------------------!
            zeta   = zoobukhov(rib,zref-dheight,rough,zoz0m,lnzoz0m,zoz0h,lnzoz0h,stable)
            !------------------------------------------------------------------------------!


            !----- Find the coefficient to scale the other stars. -------------------------!
            zeta0m = rough * zeta / (zref-dheight)
            zeta0h = z0hoz0m * zeta0m
            !------------------------------------------------------------------------------!


            !----- Find ustar, making sure it is not too small. ---------------------------!
            ustar = max (ustmin, vonk * uuse                                               &
                               / (lnzoz0m - psim(zeta,stable) + psim(zeta0m,stable)))
            !------------------------------------------------------------------------------!


            !----- Find the coefficient to scale the other stars. -------------------------!
            c3    = vonk                                                                   &
                  / (tprandtl * (lnzoz0h - psih(zeta,stable) + psih(zeta0h,stable)))
            !------------------------------------------------------------------------------!


            !------------------------------------------------------------------------------!
            !     Use potential virtual temperature here because convection is related to  !
            ! buoyancy.                                                                    !
            !------------------------------------------------------------------------------!
            tstar  = c3 * (thetav_atm - thetav_can )
            !------------------------------------------------------------------------------!


            !----- Estimate the convective velocity. --------------------------------------!
            uconv = leaf3_sflux_w(zeta,tstar,ustar) / ustar
            !------------------------------------------------------------------------------!


            !------------------------------------------------------------------------------!
            !     We are only after a rough estimate of this velocity, so if the differ-   !
            ! ence is less than the RK4 tolerance, then it's enough.                       !
            !------------------------------------------------------------------------------!
            change = 2.0 * abs(uconv-uconv_prev) / (abs(uconv) + abs(uconv_prev))
            if (change < 0.01) exit unstable
            !------------------------------------------------------------------------------!
         end do unstable
      end if
   end select

   !----- Finding all stars. --------------------------------------------------------------!
   tstar = c3 * (theta_atm    - theta_can   )
   estar = c3 * (enthalpy_atm - enthalpy_can)
   qstar = c3 * (shv_atm      - shv_can     )
   rstar = c3 * (rvap_atm     - rvap_can    )
   cstar = c3 * (co2_atm      - co2_can     )

   if (abs(tstar) < 1.e-7) tstar = 0.
   if (abs(estar) < 1.e-7) estar = 0.
   if (abs(qstar) < 1.e-7) qstar = 0.
   if (abs(rstar) < 1.e-7) rstar = 0.
   if (abs(cstar) < 1.e-7) cstar = 0.

   !---------------------------------------------------------------------------------------!
   !    Compute the ground conductance.  This equation is similar to the original, except  !
   ! that we don't assume the ratio between the gradient and the characteristic scale to   !
   ! be 0.2; instead we use the actual ratio that is computed here.                        !
   !---------------------------------------------------------------------------------------!
   ggbare = c3 * ustar
   !---------------------------------------------------------------------------------------!


   return
end subroutine leaf3_stars
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This routine computes the turbulent fluxes of momentum, heat and moisture from the    !
! surface layer using the  Manton-Cotton algebraic surface layer equations.                !
!------------------------------------------------------------------------------------------!
subroutine leaf3_sfclmcv(ustar,tstar,rstar,cstar,zeta,vels_pat,ups,vps,patch_area          &
                        ,sflux_u,sflux_v,sflux_w,sflux_t,sflux_r,sflux_c)
   use rconstants
   use leaf_coms     , only : g_urban ! ! intent(in)
   use teb_spm_start , only : teb_spm ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   real , intent(in)    :: ustar
   real , intent(in)    :: tstar
   real , intent(in)    :: rstar
   real , intent(in)    :: cstar
   real , intent(in)    :: zeta
   real , intent(in)    :: vels_pat
   real , intent(in)    :: ups
   real , intent(in)    :: vps
   real , intent(in)    :: patch_area
   real , intent(inout) :: sflux_u
   real , intent(inout) :: sflux_v
   real , intent(inout) :: sflux_w
   real , intent(inout) :: sflux_t
   real , intent(inout) :: sflux_r
   real , intent(inout) :: sflux_c
   !----- Local variables. ----------------------------------------------------------------!
   real                 :: cosine1
   real                 :: sine1
   real                 :: vtscr
   !----- Local constants. ----------------------------------------------------------------!
   real , parameter     :: wtol = 1.e-20
   !----- External functions. -------------------------------------------------------------!
   real , external      :: leaf3_sflux_w
   !---------------------------------------------------------------------------------------!

   cosine1 = ups / vels_pat
   sine1   = vps / vels_pat

   vtscr = ustar * patch_area

   !----- Check whether TEB is used. If it is, skip the lines unless g_urban is zero. -----!
   if (teb_spm /= 1 .or. nint(g_urban) == 0) then
      sflux_u = sflux_u - ustar * vtscr * cosine1
      sflux_v = sflux_v - ustar * vtscr * sine1
      sflux_t = sflux_t - tstar * vtscr
      sflux_r = sflux_r - rstar * vtscr
   end if

   !----- TEB currently doesn't save CO2, so compute sflux_c outside the if statement. ----!
   sflux_c = sflux_c - cstar * vtscr

   !----- Define vertical flux. -----------------------------------------------------------!
   sflux_w = sflux_w + leaf3_sflux_w(zeta,tstar,ustar) * patch_area

   return
end subroutine leaf3_sfclmcv
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    Vertical flux, as in:                                                                 !
!                                                                                          !
!   Manton, M. J., Cotton, W. R., 1977: Parameterization of the atmospheric surface        !
!      layer.  J. Atm. Sci., 34, 331-334.                                                  !
!------------------------------------------------------------------------------------------!
real function leaf3_sflux_w(zeta,tstar,ustar)
   use consts_coms , only : vonk ! intent(in)
  
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   real, intent(in)    :: zeta
   real, intent(in)    :: ustar
   real, intent(in)    :: tstar
   !----- Local variables -----------------------------------------------------------------!
   real                :: cx
   real                :: psin
   !----- Constants -----------------------------------------------------------------------!
   real, parameter     :: wtol = 1.e-20
   !---------------------------------------------------------------------------------------!

   if (zeta < 0.0)then
      cx = zeta * sqrt(sqrt(1.0 - 15.0 * zeta))
   else
      cx = zeta / (1.0 + 4.7 * zeta)
   endif
  
   psin = sqrt((1.0-2.86 * cx) / (1.0 + cx * (-5.390 + cx * 6.9980 )))
   leaf3_sflux_w = ( 0.27 * max(6.25 * (1.0 - cx) * psin,wtol)                             &
                       - 1.180 * cx * psin) * ustar * ustar
  
   return
end function leaf3_sflux_w
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This subroutine computes the ground properties.  By ground we mean the top soil      !
! layer if no temporary surface water/snow exists, or the top temporary surface water/snow !
! layer if it exists.                                                                      !
!                                                                                          !
! References:                                                                              !
!                                                                                          !
! Passerat de Silans, A., 1986: Transferts de masse et de chaleur dans un sol stratifi�    !
!     soumis � une excitation amtosph�rique naturelle. Comparaison: Mod�les-exp�rience.    !
!     Thesis, Institut National Polytechnique de Grenoble. (P86)                           !
!                                                                                          !
! Noilhan, J., S. Planton, 1989: Simple parameterization of land surface processes for     !
!     meteorological models, Mon. Wea. Rev., 117, 536-549. (NP89)                          !
!                                                                                          !
! Mahfouf, J. F., J. Noilhan, 1991: Comparative study of various formulations of           !
!     evaporation from bare soil using in situ data. J. Appl. Meteorol., 30, 1354-1365.    !
!     (MN91)                                                                               !
!                                                                                          !
! Lee, T. J., R. A. Pielke, 1992: Estimating the soil surface specific humidity. J. Appl.  !
!     Meteorol., 31, 480-484. (LP92)                                                       !
!                                                                                          !
! Lee, T. J., R. A. Pielke, 1993: Corrigendum. J. Appl. Meteorol., 32, 580-580. (LP93)     !
!------------------------------------------------------------------------------------------!
subroutine leaf3_grndvap(topsoil_energy,topsoil_water,topsoil_text,sfcwater_energy_int     &
                        ,sfcwater_nlev,can_rvap,can_prss,ground_rsat,ground_rvap           &
                        ,ground_temp,ground_fliq)

   use leaf_coms  , only : slcpd       & ! intent(in)
                         , slpots      & ! intent(in)
                         , slmsts      & ! intent(in)
                         , soilcp      & ! intent(in)
                         , slbs        & ! intent(in)
                         , sfldcap     & ! intent(in)
                         , ggsoil      & ! intent(in)
                         , ggsoil0     & ! intent(in)
                         , kksoil      ! ! intent(in)
   use rconstants , only : gorh2o      & ! intent(in)
                         , pi1         & ! intent(in)
                         , wdns        & ! intent(in)
                         , lnexp_min   & ! intent(in)
                         , huge_num    ! ! intent(in)
   use therm_lib  , only : rslif       & ! function
                         , uextcm2tl   & ! function
                         , uint2tl     ! ! function
   use mem_leaf   , only : igrndvap    ! ! intent(in)

   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   real, intent(in)  :: topsoil_energy      ! Top soil internal energy          [     J/m�]
   real, intent(in)  :: topsoil_water       ! Top soil water content            [m�_h2o/m�]
   real, intent(in)  :: topsoil_text        ! Top soil texture class            [      ---]
   real, intent(in)  :: sfcwater_energy_int ! Soil internal energy              [     J/kg]
   real, intent(in)  :: sfcwater_nlev       ! # active levels of surface water  [      ---]
   real, intent(in)  :: can_rvap            ! Canopy vapour mixing ratio        [kg_vap/kg]
   real, intent(in)  :: can_prss            ! Canopy pressure                   [       Pa]
   real, intent(out) :: ground_rsat         ! Surface (saturation) mixing ratio [kg_vap/kg]
   real, intent(out) :: ground_rvap         ! Ground equilibrium mixing ratio   [kg_vap/kg]
   real, intent(out) :: ground_temp         ! Surface temperature               [        K]
   real, intent(out) :: ground_fliq         ! Frac. of sfc H2O in liquid phase  [      ---]
   !----- Local variables. ----------------------------------------------------------------!
   integer           :: ksn                 ! # active levels of surface water
   integer           :: nsoil               ! Soil texture class                [      ---]
   real              :: slpotvn             ! soil water potential              [        m]
   real              :: alpha               ! "alpha" term in LP92
   real              :: beta                ! "beta" term in LP92
   real              :: lnalpha             ! ln(alpha)
   real              :: smterm              ! soil moisture term                [     ----]
   !---------------------------------------------------------------------------------------!


   !----- Set the number of temporary surface water (or snow) layers. ---------------------!
   ksn = nint(sfcwater_nlev)


   !---------------------------------------------------------------------------------------!
   !    Ground_rsat is the saturation mixing ratio of the top soil/snow surface and is     !
   ! used for dew formation and snow evaporation.  
   !---------------------------------------------------------------------------------------!
   select case (ksn)
   case (0)
      !------------------------------------------------------------------------------------!
      !      Without snowcover or water ponding, ground_shv is the effective specific      !
      ! humidity of soil and is used for soil evaporation.  This value is a combination of !
      ! the canopy air specific humidity, the saturation specific humidity at the soil     !
      ! temperature.  When the soil tends to dry air soil moisture, ground_shv tends to    !
      ! the canopy air space specific humidity, whereas it tends to the saturation value   !
      ! when the soil moisture is near or above field capacity.  These tendencies will be  !
      ! determined by the alpha and beta parameters.                                       !
      !------------------------------------------------------------------------------------!
      nsoil = nint(topsoil_text)
      call uextcm2tl(topsoil_energy,topsoil_water*wdns,slcpd(nsoil),ground_temp,ground_fliq)
      !----- Compute the saturation mixing ratio at ground temperature. -------------------!
      ground_rsat = rslif(can_prss,ground_temp)
      !------------------------------------------------------------------------------------!


      !----- Determine alpha. -------------------------------------------------------------!
      slpotvn  = slpots(nsoil) * (slmsts(nsoil) / topsoil_water) ** slbs(nsoil)
      lnalpha  = gorh2o * slpotvn / ground_temp
      if (lnalpha > lnexp_min) then
         alpha = exp(lnalpha)
      else
         alpha = 0.0
      end if
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !     Determine Beta, following NP89.  However, because we want evaporation to be    !
      ! shut down when the soil approaches the dry air soil moisture, we offset both the   !
      ! soil moisture and field capacity to the soil moisture above dry air soil.  This is !
      ! necessary to avoid evaporation to be large just slightly above the dry air soil,   !
      ! which was happening especially for those clay-rich soil types.                     !
      !------------------------------------------------------------------------------------!
      smterm     = (topsoil_water - soilcp(nsoil)) / (sfldcap(nsoil) - soilcp(nsoil))
      beta       = .5 * (1. - cos (min(1.,smterm) * pi1))
      !------------------------------------------------------------------------------------!




      !------------------------------------------------------------------------------------!
      !     Decide which method to use to find the ground water vapour mixing ratio.       !
      !------------------------------------------------------------------------------------!
      select case (igrndvap)
      case (0)
         !----- LP92 method. --------------------------------------------------------------!
         ground_rvap = max(can_rvap, ground_rsat * alpha * beta + (1. - beta) * can_rvap)
         !---------------------------------------------------------------------------------!

      case (1)
         !----- MH91, test 1. -------------------------------------------------------------!
         ground_rvap = max(can_rvap, ground_rsat * beta)
         ggsoil      = huge_num
         !---------------------------------------------------------------------------------!

      case (2)
         !----- MH91, test 2. -------------------------------------------------------------!
         ground_rvap = ground_rsat
         ggsoil      = ggsoil0 * exp(kksoil * smterm)
         !---------------------------------------------------------------------------------!

      case (3)
         !----- MH91, test 3. -------------------------------------------------------------!
         ground_rvap = max(can_rvap, ground_rsat * beta + (1. - beta) * can_rvap)
         ggsoil      = huge_num
         !---------------------------------------------------------------------------------!

      case (4)
         !---------------------------------------------------------------------------------!
         !     MH91, test 4.                                                               !
         !---------------------------------------------------------------------------------!
         ground_rvap = max(can_rvap, ground_rsat * alpha)
         ggsoil      = ggsoil0 * exp(kksoil * smterm)
         !---------------------------------------------------------------------------------!

      case (5)
         !---------------------------------------------------------------------------------!
         !     Combination of NP89 and P86.                                                !
         !---------------------------------------------------------------------------------!
         ground_rvap = max(can_rvap, ground_rsat * beta)
         ggsoil      = ggsoil0 * exp(kksoil * smterm)
         !---------------------------------------------------------------------------------!

      end select

   case default
      !------------------------------------------------------------------------------------!
      !    If a temporary layer exists, we use the top layer as the surface.  Since this   !
      ! is "pure" water or snow, we let it evaporate freely.  We can understand  this as   !
      ! the limit of alpha and beta tending to one.                                        !
      !------------------------------------------------------------------------------------!
      call uint2tl(sfcwater_energy_int,ground_temp,ground_fliq)
      !----- Compute the saturation specific humidity at ground temperature. --------------!
      ground_rsat = rslif(can_prss,ground_temp)
      !----- The ground specific humidity in this case is just the saturation value. ------!
      ground_rvap = ground_rsat
      !----- The conductance should be large so it won't contribute to the net value. -----!
      ggsoil      = huge_num
      !------------------------------------------------------------------------------------!
   end select

   return
end subroutine leaf3_grndvap
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine sfc_fields(m1,m2,m3,ia,iz,ja,jz,jd,thp,theta,rv,rtp,co2p,up,vp,dn0,pp,pi0,rtgt  &
                     ,zt,zm,thils2,ths2,rvs2,rtps2,co2s2,ups2,vps2,pis2,dens2,zts2)

   use leaf_coms
   use rconstants

   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                  , intent(in)    :: m1
   integer                  , intent(in)    :: m2
   integer                  , intent(in)    :: m3
   integer                  , intent(in)    :: ia
   integer                  , intent(in)    :: iz
   integer                  , intent(in)    :: ja
   integer                  , intent(in)    :: jz
   integer                  , intent(in)    :: jd
   real, dimension(m1,m2,m3), intent(in)    :: thp
   real, dimension(m1,m2,m3), intent(in)    :: theta
   real, dimension(m1,m2,m3), intent(in)    :: rv
   real, dimension(m1,m2,m3), intent(in)    :: rtp
   real, dimension(m1,m2,m3), intent(in)    :: co2p
   real, dimension(m1,m2,m3), intent(in)    :: up
   real, dimension(m1,m2,m3), intent(in)    :: vp
   real, dimension(m1,m2,m3), intent(in)    :: dn0
   real, dimension(m1,m2,m3), intent(in)    :: pp
   real, dimension(m1,m2,m3), intent(in)    :: pi0
   real, dimension(m1)      , intent(in)    :: zt
   real, dimension(m1)      , intent(in)    :: zm
   real, dimension(m2,m3)   , intent(in)    :: rtgt
   real, dimension(m2,m3)   , intent(inout) :: thils2
   real, dimension(m2,m3)   , intent(inout) :: ths2
   real, dimension(m2,m3)   , intent(inout) :: rvs2
   real, dimension(m2,m3)   , intent(inout) :: rtps2
   real, dimension(m2,m3)   , intent(inout) :: co2s2
   real, dimension(m2,m3)   , intent(inout) :: ups2
   real, dimension(m2,m3)   , intent(inout) :: vps2
   real, dimension(m2,m3)   , intent(inout) :: pis2
   real, dimension(m2,m3)   , intent(inout) :: dens2
   real, dimension(m2,m3)   , intent(inout) :: zts2
   !----- Local variables. ----------------------------------------------------------------!
   integer                                  :: i
   integer                                  :: j
   !---------------------------------------------------------------------------------------!



   !----- Compute surface atmospheric conditions. -----------------------------------------!
   do j = ja,jz
      do i = ia,iz
         thils2(i,j) = thp  (2,i,j)
         ths2  (i,j) = theta(2,i,j)
         rvs2  (i,j) = rv   (2,i,j)
         rtps2 (i,j) = rtp  (2,i,j)
         co2s2 (i,j) = co2p (2,i,j)
         ups2  (i,j) = (up(2,i-1,j) + up(2,i,j))  * .5
         vps2  (i,j) = (vp(2,i,j-jd) + vp(2,i,j)) * .5
         zts2  (i,j) = (zt(2)-zm(1)) * rtgt(i,j)
         pis2  (i,j) = 0.5 * (pp(1,i,j) + pi0(1,i,j) + pp(2,i,j) + pi0(2,i,j))
         dens2 (i,j) = (dn0(1,i,j) + dn0(2,i,j))  * .5
      end do
   end do

   return
end subroutine sfc_fields
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine sfc_fields_adap(m1,m2,m3,ia,iz,ja,jz,jd,flpu,flpv,flpw,topma,aru,arv,thp,theta  &
                          ,rv,rtp,co2p,up,vp,dn0,pp,pi0,zt,zm,dzt,thils2,ths2,rvs2,rtps2   &
                          ,co2s2,ups2,vps2,pis2,dens2,zts2)

   use leaf_coms
   use rconstants

   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                  , intent(in)    :: m1
   integer                  , intent(in)    :: m2
   integer                  , intent(in)    :: m3
   integer                  , intent(in)    :: ia
   integer                  , intent(in)    :: iz
   integer                  , intent(in)    :: ja
   integer                  , intent(in)    :: jz
   integer                  , intent(in)    :: jd
   real, dimension(m1,m2,m3), intent(in)    :: aru
   real, dimension(m1,m2,m3), intent(in)    :: arv
   real, dimension(m1,m2,m3), intent(in)    :: thp
   real, dimension(m1,m2,m3), intent(in)    :: theta
   real, dimension(m1,m2,m3), intent(in)    :: rv
   real, dimension(m1,m2,m3), intent(in)    :: rtp
   real, dimension(m1,m2,m3), intent(in)    :: co2p
   real, dimension(m1,m2,m3), intent(in)    :: up
   real, dimension(m1,m2,m3), intent(in)    :: vp
   real, dimension(m1,m2,m3), intent(in)    :: dn0
   real, dimension(m1,m2,m3), intent(in)    :: pp
   real, dimension(m1,m2,m3), intent(in)    :: pi0
   real, dimension(m1)      , intent(in)    :: zt
   real, dimension(m1)      , intent(in)    :: zm
   real, dimension(m1)      , intent(in)    :: dzt
   real, dimension(m2,m3)   , intent(in)    :: flpu
   real, dimension(m2,m3)   , intent(in)    :: flpv
   real, dimension(m2,m3)   , intent(in)    :: flpw
   real, dimension(m2,m3)   , intent(in)    :: topma
   real, dimension(m2,m3)   , intent(inout) :: thils2
   real, dimension(m2,m3)   , intent(inout) :: ths2
   real, dimension(m2,m3)   , intent(inout) :: rvs2
   real, dimension(m2,m3)   , intent(inout) :: rtps2
   real, dimension(m2,m3)   , intent(inout) :: co2s2
   real, dimension(m2,m3)   , intent(inout) :: ups2
   real, dimension(m2,m3)   , intent(inout) :: vps2
   real, dimension(m2,m3)   , intent(inout) :: pis2
   real, dimension(m2,m3)   , intent(inout) :: dens2
   real, dimension(m2,m3)   , intent(inout) :: zts2
   !----- Local variables. ----------------------------------------------------------------!
   integer                                  :: i
   integer                                  :: j
   integer                                  :: k1
   integer                                  :: k2
   integer                                  :: k3
   real                                     :: topma_t
   real                                     :: wtw
   real                                     :: wtu1
   real                                     :: wtu2
   real                                     :: wtv1
   real                                     :: wtv2
   !---------------------------------------------------------------------------------------!


   !----- Compute surface atmospheric conditions. -----------------------------------------!

   do j = ja,jz
      do i = ia,iz
         k2 = nint(flpw(i,j))
         k1 = k2 - 1
         k3 = k2 + 1

         topma_t = .25 * (topma(i,j) + topma(i-1,j) + topma(i,j-jd) + topma(i-1,j-jd))

         !----- Weights for lowest predicted points, relative to points above them. -------!
         wtw  = (zm(k2) - topma_t) * dzt(k2)
         wtu1 = aru(nint(flpu(i-1,j)),i-1,j)   / aru(nint(flpu(i-1,j))+1,i-1,j)
         wtu2 = aru(nint(flpu(i,j)),i,j)       / aru(nint(flpu(i,j))+1,i,j)
         wtv1 = arv(nint(flpv(i,j-jd)),i,j-jd) / arv(nint(flpv(i,j-jd))+1,i,j-jd)
         wtv2 = arv(nint(flpv(i,j)),i,j)       / arv(nint(flpv(i,j))+1,i,j)

         !----- Interpolate the values to with height. ------------------------------------!
         thils2(i,j) =  wtw * thp  (k2,i,j) + (1. - wtw)  * thp  (k3,i,j)
         ths2  (i,j) =  wtw * theta(k2,i,j) + (1. - wtw)  * theta(k3,i,j)
         rvs2  (i,j) =  wtw * rv   (k2,i,j) + (1. - wtw)  * rv   (k3,i,j)
         rtps2 (i,j) =  wtw * rtp  (k2,i,j) + (1. - wtw)  * rtp  (k3,i,j)

         co2s2(i,j) =  wtw * co2p(k2,i,j)  + (1. - wtw)  * co2p(k3,i,j)

         ups2(i,j) = (wtu1        * up(nint(flpu(i-1,j)),i-1,j)                            &
                   +  (1. - wtu1) * up(nint(flpu(i-1,j))+1,i-1,j)                          &
                   +  wtu2        * up(nint(flpu(i,j)),i,j)                                &
                   +  (1. - wtu2) * up(nint(flpu(i,j))+1,i,j)) * .5

         vps2(i,j) = (wtv1        * vp(nint(flpv(i,j-jd)),i,j-jd)                          &
                   +  (1. - wtv1) * vp(nint(flpv(i,j-jd))+1,i,j-jd)                        &
                   +  wtv2        * vp(nint(flpv(i,j)),i,j)                                &
                   +  (1. - wtv2) * vp(nint(flpv(i,j))+1,i,j)) * .5

         zts2(i,j) = (wtw * (zt(k2) - zm(k1)) + (1. - wtw) * (zt(k3) - zm(k2)))

         if (wtw >= .5) then
            pis2(i,j)  = ( (wtw - .5) * (pp(k1,i,j) + pi0(k1,i,j))                         &
                         + (1.5 - wtw) * (pp(k2,i,j) + pi0(k2,i,j)))
            dens2(i,j) = (wtw - .5)  * dn0(k1,i,j) + (1.5 - wtw) * dn0(k2,i,j)
         else
            pis2(i,j)  = ( (wtw + .5) * (pp(k2,i,j) + pi0(k2,i,j))                         &
                         + (.5 - wtw) * (pp(k3,i,j) + pi0(k3,i,j)))
            dens2(i,j) = (wtw + .5) * dn0(k2,i,j) + (.5 - wtw) * dn0(k3,i,j)
         end if

      end do
   end do

   return
end subroutine sfc_fields_adap
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine sfc_pcp(m2,m3,mcld,ia,iz,ja,jz,dtime,dtime_factor,theta2,exner2,conprr,bulkpcpg &
                  ,bulkqpcpg,bulkdpcpg,leafpcpg,leafqpcpg,leafdpcpg)
   use rconstants, only : t3ple        & ! intent(in)
                        , t00          & ! intent(in)
                        , hr_sec       & ! intent(in)
                        , wdnsi        ! ! intent(in)
   use node_mod  , only : mynum        ! ! intent(in)
   use grid_dims , only : str_len      ! ! intent(in)
   use therm_lib , only : tl2uint      & ! function
                        , extheta2temp ! ! function
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                       , intent(in)    :: m2
   integer                       , intent(in)    :: m3
   integer                       , intent(in)    :: mcld
   integer                       , intent(in)    :: ia
   integer                       , intent(in)    :: iz
   integer                       , intent(in)    :: ja
   integer                       , intent(in)    :: jz
   real                          , intent(in)    :: dtime
   real                          , intent(in)    :: dtime_factor
   real   , dimension(m2,m3)     , intent(in)    :: theta2
   real   , dimension(m2,m3)     , intent(in)    :: exner2
   real   , dimension(m2,m3,mcld), intent(in)    :: conprr
   real   , dimension(m2,m3)     , intent(in)    :: bulkpcpg
   real   , dimension(m2,m3)     , intent(in)    :: bulkqpcpg
   real   , dimension(m2,m3)     , intent(in)    :: bulkdpcpg
   real   , dimension(m2,m3)     , intent(inout) :: leafpcpg
   real   , dimension(m2,m3)     , intent(inout) :: leafqpcpg
   real   , dimension(m2,m3)     , intent(inout) :: leafdpcpg
   !----- Local variables. ----------------------------------------------------------------!
   character(len=str_len)                        :: rainfile
   integer                                       :: i
   integer                                       :: j
   integer                                       :: icld
   real                                          :: rain_temp
   real                                          :: fice
   real                                          :: sndeni
   real                                          :: cumpcpg
   real                                          :: cumqpcpg
   real                                          :: cumdpcpg
   !----- Local constants. ----------------------------------------------------------------!
   logical                       , parameter     :: print_rain = .false.
   character(len=10)             , parameter     :: fmth       = '(17(a,1x))' 
   character(len=25)             , parameter     :: fmtb       = '(2(i5,1x),15(es12.5,1x))' 
   !----- Locally saved variables. --------------------------------------------------------!
   logical                       , save          :: first_time = .true. 
   !---------------------------------------------------------------------------------------!


   !----- Re-create the file in case this is the first time the routine is called. --------!
   if (print_rain .and. first_time) then
      first_time = .false.
      write (rainfile,fmt='(a,i3.3,a)') 'rainleaf-',mynum,'.txt'

      open  (unit=63,file=trim(rainfile),status='replace',action='write')
      write (unit=63,fmt=fmth) '    I','    J','       DTIME','DTIME_FACTOR'               &
                               ,'       THETA','       EXNER','       RTEMP'               &
                               ,'      CONPRR','    CUM_PCPG','   CUM_QPCPG'               &
                               ,'   CUM_DPCPG','   BULK_PCPG','  BULK_QPCPG'               &
                               ,'  BULK_DPCPG','   LEAF_PCPG','  LEAF_QPCPG'               &
                               ,'  LEAF_DPCPG'
      close (unit=63,status='keep')
   end if
   !---------------------------------------------------------------------------------------!



   !----- Initialise the precipitation variables. -----------------------------------------!
   leafpcpg (:,:) = 0.
   leafqpcpg(:,:) = 0.
   leafdpcpg(:,:) = 0.


   !----- Loop over the horizontal domain. ------------------------------------------------!
   jloop: do j=ja,jz
      iloop: do i=ia,iz

         !----- Estimate the precipitation temperature. -----------------------------------!
         rain_temp     = extheta2temp(exner2(i,j),theta2(i,j))


         !----- Integrate precipitation rate. ---------------------------------------------!
         cumpcpg = 0.
         cloop: do icld =1,mcld
            cumpcpg = cumpcpg + conprr(i,j,icld) * dtime
         end do cloop



         !---------------------------------------------------------------------------------!
         !  Precipitation "depth". Snow fraction and density derived from                  !
         !  Jin et al 1999 Hydrol Process. 13:2467-2482 Table 2                            !
         !  [[modified 11/16/09 by MCD]]                                                   !
         !---------------------------------------------------------------------------------!
         if (rain_temp > (t3ple + 2.5)) then
            !----- Rain only. -------------------------------------------------------------!
            fice    = 0.0
            sndeni  = 1. / 189.0

         elseif (rain_temp <= (t3ple + 2.5) .and. rain_temp  > (t3ple + 2.0) ) then
            !------------------------------------------------------------------------------!
            !     60% snow, 40% rain. (N.B. May not be appropriate for sub-tropical        !
            ! regions where the level of the melting layer is higher...).                  !
            !------------------------------------------------------------------------------!
            fice    = 0.6
            sndeni  = 1. / 189.0

         elseif (rain_temp <= (t3ple + 2.0) .and. rain_temp > t3ple ) then
            !------------------------------------------------------------------------------!
            !     Increasing the fraction of snow. (N.B. May not be appropriate for        !
            ! sub-tropical regions where the level of the melting layer is higher...).     !
            !------------------------------------------------------------------------------!
            fice   = min(1.0, 1. + (54.62 - 0.2*rain_temp))
            sndeni = 1. / (50.0+1.7*(rain_temp-258.15)**1.5 )

         elseif (rain_temp <= t3ple .and. rain_temp > (t3ple - 15.0)) then
            !----- Below freezing point, snow only. ---------------------------------------!
            fice   = 1.0
            sndeni = 1. / (50.0+1.7*(rain_temp-258.15)**1.5 )

         else ! if (rain_temp < (t3ple - 15.0)) then
            !----- Below freezing point, snow only. ---------------------------------------!
            fice   = 1.0
            sndeni = 1. / 50.
         end if
         cumdpcpg  = cumpcpg * ((1.0-fice) * wdnsi + fice * sndeni)
         !---------------------------------------------------------------------------------!



         !---------------------------------------------------------------------------------!
         !     Set internal energy.  This will be the precipitation times the specific     !
         ! internal energy of water (above or at triple point) multiplied by the liquid    !
         ! fraction plus the specific internal energy of ice (below or at the triple       !
         ! point) multiplied by the ice fraction.                                          !
         !---------------------------------------------------------------------------------!
         cumqpcpg = cumpcpg  * ( (1.0-fice) * tl2uint(max(t3ple,rain_temp),1.0)            &
                               +      fice  * tl2uint(min(rain_temp,t3ple),0.0) )
         !---------------------------------------------------------------------------------!



         !---------------------------------------------------------------------------------!
         !     Leaf total precipitation, and associated internal energy and depth, is the  !
         ! total amount integrated over one leaf time step.                                !
         !---------------------------------------------------------------------------------!
         leafpcpg(i,j)  = cumpcpg   + dtime_factor * bulkpcpg (i,j)
         leafqpcpg(i,j) = cumqpcpg  + dtime_factor * bulkqpcpg(i,j)
         leafdpcpg(i,j) = cumdpcpg  + dtime_factor * bulkdpcpg(i,j)
         !---------------------------------------------------------------------------------!

         if (leafpcpg(i,j) > 0.0 .and. print_rain) then
            write (rainfile,fmt='(a,i3.3,a)') 'rainleaf-',mynum,'.txt'
            open  (unit=63,file=trim(rainfile),status='old',action='write'                 &
                  ,position='append')
            write (unit=63,fmt=fmtb)  i,j,dtime,dtime_factor,theta2(i,j),exner2(i,j)       &
                                    , rain_temp-t00,conprr(i,j,1)*hr_sec                   &
                                    , cumpcpg      ,cumqpcpg      ,cumdpcpg*1000.          &
                                    , bulkpcpg(i,j),bulkqpcpg(i,j),bulkdpcpg(i,j)*1000.    &
                                    , leafpcpg(i,j),leafqpcpg(i,j),leafdpcpg(i,j)*1000.
            close (unit=63,status='keep')
         end if
      end do iloop
   end do jloop

   return
end subroutine sfc_pcp
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This subroutine computes the NDVI-related variables such as LAI, TAI, roughness,     !
! and albedo.                                                                              !
!------------------------------------------------------------------------------------------!
subroutine vegndvi(ifm,patch_area,leaf_class,veg_fracarea,veg_lai,veg_tai,veg_rough        &
                  ,veg_height,veg_displace,veg_albedo,veg_ndvip,veg_ndvic,veg_ndvif        &
                  ,psibar_10d)

   use leaf_coms
   use rconstants
   use io_params
   use mem_grid
   use catt_start, only: catt  ! INTENT(IN)

   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                         , intent(in)    :: ifm
   real                            , intent(in)    :: patch_area
   real                            , intent(in)    :: leaf_class
   real                            , intent(in)    :: veg_height
   real                            , intent(in)    :: veg_ndvip
   real                            , intent(in)    :: veg_ndvif
   real                            , intent(out)   :: veg_lai
   real                            , intent(out)   :: veg_tai
   real                            , intent(out)   :: veg_fracarea
   real                            , intent(out)   :: veg_displace
   real                            , intent(out)   :: veg_rough
   real                            , intent(out)   :: veg_albedo
   real                            , intent(inout) :: veg_ndvic
   real                            , intent(in)    :: psibar_10d
   !----- Local variables. ----------------------------------------------------------------!
   integer                                         :: nveg
   real                                            :: sr
   real                                            :: fpar
   real                                            :: dead_lai
   real                                            :: green_frac
   !----- Local constants. ----------------------------------------------------------------!
   real                            , parameter     :: sr_min     =  1.081
   real                            , parameter     :: fpar_min   =  0.001
   real                            , parameter     :: fpar_max   =  0.950
   real                            , parameter     :: fpcon      = -0.3338082
   real                            , parameter     :: ccc        = -2.9657
   real                            , parameter     :: bz         =  0.91
   real                            , parameter     :: hz         =  0.0075
   real                            , parameter     :: extinc_veg = 0.75
   !----- Locally saved variables. --------------------------------------------------------!
   logical                         , save          :: nvcall     = .true.
   real, dimension(nvtyp+nvtyp_teb), save          :: dfpardsr
   !---------------------------------------------------------------------------------------!


   !----- Initialise the dfpardsr array, which will be used to compute LAI. ---------------!
   if (nvcall) then
      nvcall = .false.
      do nveg = 1,(nvtyp+nvtyp_teb)
         dfpardsr(nveg) = (fpar_max - fpar_min) / (sr_max(nveg) - sr_min)
      end do
   end if



   !----- Find the time interpolation factor for updating NDVI or LAI. --------------------!
   if (iupdndvi == 0) then
      timefac_ndvi = 0.
   else
      timefac_ndvi = sngl((time - ndvitime1(ifm)) / (ndvitime2(ifm) - ndvitime1(ifm)))
   end if
   !---------------------------------------------------------------------------------------!



   !----- Alias for vegetation class. -----------------------------------------------------!
   nveg = nint(leaf_class)

   !---------------------------------------------------------------------------------------!
   !    We only compute LAI and related variables for those vegetation types that can hold !
   ! some actual vegetation.                                                               !
   !---------------------------------------------------------------------------------------!
   if (tai_max(nveg) < .1) then
      veg_lai      = 0.
      veg_tai      = 0.
      veg_rough    = 0.
      veg_albedo   = 0.
      veg_fracarea = 0.

   else
      
      !------------------------------------------------------------------------------------!
      !  Time-interpolate NDVI to get current value veg_ndvic(i,j) for this patch.  Limit  !
      ! NDVI to prevent values > .99 to prevent division by zero.                          !
      !------------------------------------------------------------------------------------!

      if (iuselai == 1) then
         veg_ndvic = max(0.0,veg_ndvip + (veg_ndvif - veg_ndvip) * timefac_ndvi)
      else
         !---------------------------------------------------------------------------------!
         !     Time-interpolate ndvi to get current value veg_ndvic(i,j) for this patch.   !
         ! Limit NDVI to prevent values > .99 to prevent division by zero.                 !
         !---------------------------------------------------------------------------------!
         veg_ndvic = max(0.99,veg_ndvip + (veg_ndvif - veg_ndvip) * timefac_ndvi)


         !---------------------------------------------------------------------------------!
         ! Based on SRF's suggestion - MODIS sometimes has weird values of NDVI for        !
         !                             evergreen forests, so we impose a lower threshold   !
         !                             for this vegetation type.                           !
         ! (Maybe we should try using something better than NDVI, perhaps EVI?)            !
         !---------------------------------------------------------------------------------!
         if (nveg == 7) veg_ndvic = max(0.7,veg_ndvic)
         
      end if
      !------------------------------------------------------------------------------------!


      !------------------------------------------------------------------------------------!
      !     Here we decide which way we are going to compute LAI.  If NDVIFLG is 0 or 2,   !
      ! we use LEAF-3 phenology, otherwise we use NDVI to prescribe LAI.                   !
      !------------------------------------------------------------------------------------!
      select case (ndviflg(ifm))
      case (1)
         !------ We've read information from files, use it. -------------------------------!

         if (iuselai == 1) then
            !----- Input data were LAI, copy it. ------------------------------------------!
            veg_lai = veg_ndvic

         else

            !----- Compute "simple ratio" and limit between sr_min and sr_max(nveg). ------!
            sr = min(sr_max(nveg), max(sr_min, (1. + veg_ndvic) / (1. - veg_ndvic) ) )


            !----- Compute fpar. ----------------------------------------------------------!
            fpar = fpar_min + (sr - sr_min) * dfpardsr(nveg)

            !------------------------------------------------------------------------------!
            !      Compute green leaf area index (veg_lai), dead leaf area index           !
            ! (dead_lai), total area index (tai), and green fraction.                      !
            !------------------------------------------------------------------------------!
            veg_lai    = glai_max(nveg) * (       veg_clump(nveg)  * fpar / fpar_max       &
                                          + (1. - veg_clump(nveg)) * alog(1. - fpar)       &
                                          * fpcon )
         end if

      case default
         !---------------------------------------------------------------------------------!
         !    We haven't read anything, use the table value, scaled by phenology if needed !
         ! by this PFT.                                                                    !
         !---------------------------------------------------------------------------------!
         select case (phenology(nveg))
         case (4)
            !----- Use drought/cold phenology. --------------------------------------------!
            veg_lai = glai_max(nveg) * max(0.02,min(1.0,psibar_10d))
         case default
            !----- Evergreen. -------------------------------------------------------------!
            veg_lai = glai_max(nveg)
         end select
      end select
      dead_lai   = (glai_max(nveg) - veg_lai) * dead_frac(nveg)
      veg_tai    = veg_lai + sai(nveg) + dead_lai
      green_frac = veg_lai / veg_tai

      !----- Compute vegetation roughness height, albedo, and fractional area. ------------!
      veg_rough    = veg_height * (1. - bz * exp(-hz * veg_tai))
      veg_displace = veg_height * vh2dh
      veg_albedo   = albv_green(nveg) * green_frac + albv_brown(nveg) * (1. - green_frac)
      veg_fracarea = veg_frac(nveg) * (1. - exp(-extinc_veg * veg_tai))
   end if

   return
end subroutine vegndvi
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This routine is called by the radiation parameterization and by LEAF.  It computes   !
! net surface albedo plus radiative exchange between the atmosphere, vegetation, and the   !
! snow/ground given previously computed downward longwave and shortwave fluxes from the    !
! atmosphere.  Also computed are functions of snowcover that are required for the above    !
! radiation calculations as well as other calculations in LEAF.                            !
!     The shortwave parameterizations are only valid if the cosine of the zenith angle is  !
! greater than .03 .  Water albedo from Atwater and Bell (1981) alg, als, and alv are the  !
! albedos of the ground, snow, and vegetation (als needs a better formula based on age of  !
! the surface snow).  absg and vctr32 are the actual fractions of shortwave incident on    !
! snow plus ground that get absorbed by the ground and each snow layer, respectively.      !
! They currently use the variable fractrans, which is the fraction of light transmitted    !
! through each layer based on mass per square meter.  algs is the resultant albedo from    !
! snow plus ground.                                                                        !
!------------------------------------------------------------------------------------------!
subroutine leaf3_sfcrad(mzg,mzs,ip,soil_water,soil_color,soil_text,sfcwater_depth          &
                       ,patch_area,veg_fracarea,leaf_class,veg_albedo,sfcwater_nlev,rshort &
                       ,rlong,cosz,albedt,rlongup,rshort_gnd,rlong_gnd)
   use mem_leaf
   use leaf_coms
   use rconstants
   use mem_scratch
   use node_mod     , only : mynum         ! ! intent(in)
   use therm_lib    , only : uextcm2tl     & ! subroutine
                           , idealdenssh   ! ! function
   use catt_start   , only : CATT          ! ! intent(in)
   use teb_spm_start, only : TEB_SPM       ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                , intent(in)    :: mzg
   integer                , intent(in)    :: mzs
   integer                , intent(in)    :: ip
   real   , dimension(mzg), intent(in)    :: soil_water
   real                   , intent(in)    :: soil_color
   real   , dimension(mzg), intent(in)    :: soil_text
   real   , dimension(mzs), intent(in)    :: sfcwater_depth 
   real                   , intent(in)    :: patch_area
   real                   , intent(in)    :: veg_fracarea
   real                   , intent(in)    :: leaf_class
   real                   , intent(in)    :: veg_albedo
   real                   , intent(in)    :: sfcwater_nlev
   real                   , intent(in)    :: rshort
   real                   , intent(in)    :: rlong
   real                   , intent(in)    :: cosz
   real                   , intent(inout) :: albedt
   real                   , intent(inout) :: rlongup
   real                   , intent(inout) :: rshort_gnd
   real                   , intent(inout) :: rlong_gnd
   !----- Local variables. ----------------------------------------------------------------!
   integer                                :: k
   integer                                :: m
   integer                                :: nsoil
   integer                                :: colour
   integer                                :: nveg
   integer                                :: ksn
   real                                   :: alb
   real                                   :: vf
   real                                   :: vfc
   real                                   :: fcpct
   real                                   :: alg
   real                                   :: rad
   real                                   :: als
   real                                   :: fractrans
   real                                   :: absg
   real                                   :: algs
   real                                   :: emv
   real                                   :: emgs
   real                                   :: gslong
   real                                   :: vlong
   real                                   :: alv
   !----- Local constants. ----------------------------------------------------------------!
   character(len=9)      , parameter   :: fmti='(a,1x,i6)'
   character(len=13)     , parameter   :: fmtf='(a,1x,es12.5)'
   character(len=3)      , parameter   :: fmtc='(a)'
   character(len=9)      , parameter   :: fmtl='(a,1x,l1)'
   character(len=9)      , parameter   :: fmth='(7(a,1x))'
   character(len=23)     , parameter   :: fmts='(2(i5,1x),5(es12.5,1x))'
   character(len=9)      , parameter   :: fmte='(5(a,1x))'
   character(len=23)     , parameter   :: fmtw='(1(i5,1x),4(es12.5,1x))'
   !---------------------------------------------------------------------------------------!

   if (ip == 1) then
      !----- Compute the albedo and upward longwave for water patches. --------------------!
      if (cosz > .03) then
         alb     = min(max(-.0139 + .0467 * tan(acos(cosz)),.03),.999)
         albedt  = albedt + patch_area * alb
      else
         alb     = 0.0
      end if
      rlongup    = rlongup + patch_area * stefan * soil_tempk(mzg) ** 4

      rshort_gnd = (1.0 - alb) * rshort
      rlong_gnd  = 0.0

   elseif (isfcl == 0) then
      !------ Not running a land surface model, use prescribed value of can_temp. ---------!
      albedt     = albedt  + patch_area * albedo
      rlongup    = rlongup + patch_area * stefan * can_temp ** 4

      rshort_gnd = (1.0 - albedo) * rshort
      rlong_gnd  = 0.0
   else
      !------ Running an actual land surface model... -------------------------------------!


      !------ Diagnose snow temperature and the influence of snow covering veg. -----------!
      nveg  = nint(leaf_class)
      nsoil = nint(soil_text(mzg))
      ksn   = nint(sfcwater_nlev)

      !------ Defining the exposed area. --------------------------------------------------!
      vf  = veg_fracarea * (1. - snowfac)
      vfc = 1. - vf

      !------------------------------------------------------------------------------------!
      !     Ground albedo.  Experimental value ranging from dry to wet soil albedo, and    !
      ! using some soil texture dependence, even though soil colour depends on a lot more  !
      ! things.                                                                            !
      !------------------------------------------------------------------------------------!
      select case (nsoil)
      case (13)
         !----- Bedrock, use constants soil value for granite. ----------------------------!
         alg = 0.32
      case (12)
         !----- Peat, follow McCumber and Pielke (1981). ----------------------------------!
         fcpct = soil_water(mzg) / slmsts(nsoil)
         alg   = max (0.07, 0.14 * (1.0 - fcpct))
      case default
         !----- Other soils. --------------------------------------------------------------!
         colour = nint(soil_color)
         select case (colour)
         case (21)
            fcpct = soil_water(mzg) / slmsts(nsoil)
            alg   = max(0.14, 0.31 - 0.34 * fcpct)
         case default
            fcpct  = max (0.00, 0.11 - 0.40 * soil_water(mzg))
            alg    = min (0.5 * (alb_nir_dry(nscol) + alb_vis_dry(nscol))                  &
                         ,0.5 * (alb_nir_wet(nscol) + alb_vis_wet(nscol)) + fcpct )
         end select
      end select
      !------------------------------------------------------------------------------------!


      !------------------------------------------------------------------------------------!
      !      Vegetation albedo.                                                            !
      !------------------------------------------------------------------------------------!
      alv = veg_albedo
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !       Snow/surface water albedo.                                                   !
      !------------------------------------------------------------------------------------!
      rad = 1.
      if (ksn > 0) then
         !------ als = .14 (the wet soil value) for all-liquid. ---------------------------!
         als = .5 - .36 * sfcwater_fracliq(ksn)
         rad = 1. - als
      end if
      do k = ksn,1,-1
         fractrans = exp(-20. * sfcwater_depth(k))
         vctr32(k) = rad * (1. - fractrans)
         rad = rad * fractrans
      end do
      absg = (1. - alg) * rad
      algs = 1. - absg
      do k = ksn,1,-1
         algs = algs - vctr32(k)
         rshort_s(k) = rshort * vfc * vctr32(k)
      end do
      rshort_g = rshort * vfc * absg
      rshort_v = rshort * vf * (1. - alv + vfc * algs)
      alb      = vf * alv + vfc * vfc * algs
      !------------------------------------------------------------------------------------!



      !----- Adding urban contribution if running TEB. ------------------------------------!
      if (teb_spm==1) then
         if (nint(g_urban) == 0) then
            albedt = albedt + patch_area * alb
         else
            albedt = albedt + patch_area * alb_town
         endif
      else
         albedt = albedt + patch_area * alb
      end if
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !     Longwave radiation calculations.                                               !
      !------------------------------------------------------------------------------------!
      emv  = emisv(nveg)
      emgs = emisg(nsoil)
      if (ksn > 0) then
         emgs = 1.0
         gslong = emgs * stefan * sfcwater_tempk(ksn) ** 4
      else
         gslong = emgs * stefan * soil_tempk(mzg) ** 4
      end if
      vlong  = emv * stefan * veg_temp ** 4

      rlonga_v  = rlong  * vf * (emv + vfc * (1. - emgs))
      rlonga_gs = rlong  * vfc * emgs
      rlongv_gs = vlong  * vf * emgs
      rlongv_a  = vlong  * vf * (2. - emgs - vf + emgs * vf)
      rlonggs_v = gslong * vf * emv
      rlonggs_a = gslong * vfc
      rlonga_a  = rlong  * (vf * (1. - emv) + vfc * vfc * (1. - emgs))

      !----- Add urban contribution if running TEB. ---------------------------------------!
      if (teb_spm==1) then
         if (nint(g_urban) == 0) then
            rlongup = rlongup + patch_area * (rlongv_a + rlonggs_a + rlonga_a)
         else
            rlongup = rlongup + patch_area * emis_town * stefan * ts_town**4
         endif
      else
         rlongup = rlongup + patch_area * (rlongv_a + rlonggs_a + rlonga_a)
      endif

      !------------------------------------------------------------------------------------!
      !      In case rlong is not computed, zero out all longwave fluxes other than        !
      ! rlongup.  [On the first timestep, radiative fluxes may not be available until      !
      ! microphysics is called, and zeroing these fluxes avoids the imbalance of having    !
      ! upward longwave without downward longwave in LEAF-3.  Also, this allows LEAF-3 to  !
      ! run without radiation for all timesteps, if desired for testing.].                 !
      !------------------------------------------------------------------------------------!
      if (rlong < .1) then
         rlonga_v  = 0.
         rlonga_gs = 0.
         rlongv_gs = 0.
         rlongv_a  = 0.
         rlonggs_v = 0.
         rlonggs_a = 0.
         rlonga_a  = 0.
      end if
      !------------------------------------------------------------------------------------!



      !----- Integrate the total absorbed light by ground (top soil plus TSW layers). -----!
      rshort_gnd = rshort_g
      do k=1,ksn
         rshort_gnd = rshort_gnd + rshort_s(k)
      end do
      rlong_gnd  = rlonga_gs + rlongv_gs - rlonggs_a - rlonggs_v
      !------------------------------------------------------------------------------------!



   end if

   return
end subroutine leaf3_sfcrad
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This function determines the wind at a given height, given that the stars are al-     !
! ready known, as well as the Richardson number and the zetas.                             !
!------------------------------------------------------------------------------------------!
real(kind=4) function leaf3_reduced_wind(ustar,zeta,rib,zref,dheight,height,rough)
   use rconstants     , only : vonk     ! ! intent(in)
   use leaf_coms      , only : bl79     & ! intent(in)
                             , csm      & ! intent(in)
                             , csh      & ! intent(in)
                             , dl79     & ! intent(in)
                             , ugbmin   & ! intent(in)
                             , psim     ! ! function
   use mem_leaf       , only : istar    ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   real(kind=4), intent(in) :: ustar     ! Friction velocity                      [    m/s]
   real(kind=4), intent(in) :: zeta      ! Normalised height                      [    ---]
   real(kind=4), intent(in) :: rib       ! Bulk Richardson number                 [    ---]
   real(kind=4), intent(in) :: zref      ! Reference height                       [      m]
   real(kind=4), intent(in) :: dheight   ! Displacement height                    [      m]
   real(kind=4), intent(in) :: height    ! Height to determine the red. wind      [      m]
   real(kind=4), intent(in) :: rough     ! Roughness scale                        [      m]
   !----- Local variables. ----------------------------------------------------------------!
   logical                  :: stable    ! Canopy air space is stable             [    T|F]
   real(kind=4)             :: zetah     ! Zeta for h=height                      [    ---]
   real(kind=4)             :: zeta0     ! Zeta for h=rough                       [    ---]
   real(kind=4)             :: hoz0      ! ((h-d0)/z0)                            [    ---]
   real(kind=4)             :: lnhoz0    ! ln ((h-d0)/z0)                         [    ---]
   real(kind=4)             :: a2        ! Drag coeff. in neutral conditions
   real(kind=4)             :: fm        ! Stability parameter for momentum
   real(kind=4)             :: c2        ! Part of the c coefficient.
   real(kind=4)             :: cm        ! c coefficient times |Rib|^1/2
   real(kind=4)             :: ee        ! (z/z0)^1/3 -1. for eqn. 20 (L79)
   !----- External functions. -------------------------------------------------------------!
   real(kind=4), external   :: cbrt      ! Cubic root
   !---------------------------------------------------------------------------------------!



   !----- Define whether the layer is stable or not. --------------------------------------!
   stable    = rib >= 0.
   !---------------------------------------------------------------------------------------!



   !----- Find the log for the log-height interpolation of wind. --------------------------!
   hoz0      = (height-dheight)/rough
   lnhoz0    = log(hoz0)
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     The wind at a given height is found by using the same definition of wind speed at !
   ! a given height.                                                                       !
   !---------------------------------------------------------------------------------------!
   select case (istar)
   case (1) !---- Louis (1979) method. ----------------------------------------------------!

      !----- Compute the a-square factor and the coefficient to find theta*. --------------!
      a2   = vonk * vonk / (lnhoz0 * lnhoz0)

      if (stable) then
         !----- Stable case ---------------------------------------------------------------!
         fm = 1.0 / (1.0 + (2.0 * bl79 * rib / sqrt(1.0 + dl79 * rib)))

      else
         !---------------------------------------------------------------------------------!
         !     Unstable case.  The only difference from the original method is that we no  !
         ! longer assume z >> z0, so the "c" coefficient uses the full z/z0 term.          !
         !---------------------------------------------------------------------------------!
         ee = cbrt(hoz0) - 1.
         c2 = bl79 * a2 * ee * sqrt(ee * abs(rib))
         cm = csm * c2
         fm = (1.0 - 2.0 * bl79 * rib / (1.0 + 2.0 * cm))
      end if
      
      !----- Find the wind. ---------------------------------------------------------------!
      leaf3_reduced_wind = (ustar/vonk) * (lnhoz0/sqrt(fm))

   case default  !----- Other methods. ----------------------------------------------------!

      !----- Determine zeta for the sought height and for roughness height. ---------------!
      zetah = zeta * (height-dheight) / (zref-dheight)
      zeta0 = zeta * rough            / (zref-dheight)
      !------------------------------------------------------------------------------------!

      leaf3_reduced_wind = (ustar/vonk)                                                    &
                         * (lnhoz0 - psim(zetah,stable) + psim(zeta0,stable))

   end select
   !---------------------------------------------------------------------------------------!



   !----- Impose the wind to be more than the minimum. ------------------------------------!
   leaf3_reduced_wind = max(leaf3_reduced_wind, ugbmin)
   !---------------------------------------------------------------------------------------!


   return
end function leaf3_reduced_wind
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This sub-routine computes the aerodynamic conductance between leaf and canopy air    !
! space for both heat and water vapour, based on:                                          !
!                                                                                          !
! L95 - Leuning, R., F. M. Kelliher, D. G. G. de Pury, E. D. Schulze, 1995: Leaf           !
!       nitrogen, photosynthesis, conductance and transpiration: scaling from leaves to    !
!       canopies.  Plant, Cell and Environ., 18, 1183-1200.                                !
! M08 - Monteith, J. L., M. H. Unsworth, 2008. Principles of Environmental Physics,        !
!       3rd. edition, Academic Press, Amsterdam, 418pp.  (Mostly Chapter 10).              !
!                                                                                          !
! Notice that the units are somewhat different from L95.                                   !
! - gbh is in J/(K m2 s), and                                                              !
! - gbw is in kg_H2O/m2/s.                                                                 !
!------------------------------------------------------------------------------------------!
subroutine leaf3_aerodynamic_conductances(iveg,veg_wind,veg_temp,can_temp,can_shv,can_rhos &
                                         ,can_cp)
   use leaf_coms , only : leaf_width & ! intent(in)
                        , aflat_turb & ! intent(in)
                        , aflat_lami & ! intent(in)
                        , nflat_turb & ! intent(in)
                        , nflat_lami & ! intent(in)
                        , bflat_turb & ! intent(in)
                        , bflat_lami & ! intent(in)
                        , mflat_turb & ! intent(in)
                        , mflat_lami & ! intent(in)
                        , gbh_2_gbw  & ! intent(in)
                        , gbh        & ! intent(in)
                        , gbw        ! ! intent(in)
   use rconstants, only : t00        & ! intent(in)
                        , grav       & ! intent(in)
                        , kin_visc0  & ! intent(in)
                        , dkin_visc  & ! intent(in)
                        , th_diff0   & ! intent(in)
                        , dth_diff   ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                      :: iveg            ! Vegetation class           [      ---]
   real(kind=4)   , intent(in)  :: veg_wind        ! Wind at cohort height      [      m/s]
   real(kind=4)   , intent(in)  :: veg_temp        ! Leaf temperature           [        K]
   real(kind=4)   , intent(in)  :: can_temp        ! Canopy air temperature     [        K]
   real(kind=4)   , intent(in)  :: can_shv         ! Canopy air spec. hum.      [    kg/kg]
   real(kind=4)   , intent(in)  :: can_rhos        ! Canopy air density         [    kg/m�]
   real(kind=4)   , intent(in)  :: can_cp          ! Canopy air spec. heat      [   J/kg/K]
   !----- Local variables. ----------------------------------------------------------------!
   real(kind=4)                 :: lwidth          ! Leaf width                 [        m]
   real(kind=4)                 :: kin_visc        ! Kinematic viscosity        [     m�/s]
   real(kind=4)                 :: th_diff         ! Kinematic viscosity        [     m�/s]
   real(kind=4)                 :: th_expan        ! Thermal expansion          [      1/K]
   real(kind=4)                 :: gr_coeff        ! grav*th_expan/kin_visc�    [   1/K/m�]
   real(kind=4)                 :: grashof         ! Grashof number             [      ---]
   real(kind=4)                 :: reynolds        ! Reynolds number            [      ---]
   real(kind=4)                 :: nusselt_lami    ! Nusselt number (laminar)   [      ---]
   real(kind=4)                 :: nusselt_turb    ! Nusselt number (turb.)     [      ---]
   real(kind=4)                 :: nusselt         ! Nusselt number             [      ---]
   real(kind=4)                 :: forced_gbh_mos  ! Forced convection cond.    [      m/s]
   real(kind=4)                 :: free_gbh_mos    ! Free convection cond.      [      m/s]
   real(kind=4)                 :: gbh_mos         ! Total convection cond.     [      m/s]
   !---------------------------------------------------------------------------------------!


   !----- Save the leaf width of this PFT. ------------------------------------------------!
   lwidth = leaf_width(iveg)
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     Compute kinematic viscosity, thermal diffusivity, and expansion coefficient as    !
   ! functions of temperature.  Here we use the canopy air space temperature because       !
   ! this is the representative temperature of the fluid.                                  !
   !                                                                                       !
   !     Kinematic viscosity and thermal diffusivity are determined from MU08, see         !
   ! discussion on page 32.  Thermal expansion is assumed to be of an ideal gas (1/T),     !
   ! like in Dufour and van Mieghem (1975), for example.                                   !
   !---------------------------------------------------------------------------------------!
   th_expan = 1.0 / can_temp
   !----- kin_visc and th_diff are assumed linear functions of temperature. ---------------!
   kin_visc = kin_visc0 * ( 1.0 + dkin_visc * ( can_temp - t00 ) )
   th_diff  = th_diff0  * ( 1.0 + dth_diff  * ( can_temp - t00 ) )
   !---------------------------------------------------------------------------------------!
   !    Grashof coefficient (a*g/nu�) in MU08's equation 10.8.                             !
   !---------------------------------------------------------------------------------------!
   gr_coeff = th_expan * grav  / ( kin_visc * kin_visc )
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !     Find the conductance, in m/s, associated with forced convection.                  !
   !---------------------------------------------------------------------------------------!
   !----- 1. Compute the Reynolds number. -------------------------------------------------!
   reynolds        = veg_wind * lwidth / th_diff
   !----- 2. Compute the Nusselt number for both the laminar and turbulent case. ----------!
   nusselt_lami    = aflat_lami * reynolds ** nflat_lami
   nusselt_turb    = aflat_turb * reynolds ** nflat_turb
   !----- 4. The right Nusselt number is the largest. -------------------------------------!
   nusselt         = max(nusselt_lami,nusselt_turb)
   !----- 5. The conductance is given by MU08 - equation 10.4 -----------------------------!
   forced_gbh_mos  = th_diff * nusselt / lwidth
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     Find the conductance, in m/s,  associated with free convection.                   !
   !---------------------------------------------------------------------------------------!
   !----- 1. Find the Grashof number. -----------------------------------------------------!
   grashof         = gr_coeff  * abs(veg_temp - can_temp) * lwidth * lwidth * lwidth
   !----- 2. Compute the Nusselt number for both the laminar and turbulent case. ----------!
   nusselt_lami    = bflat_lami * grashof ** mflat_lami
   nusselt_turb    = bflat_turb * grashof ** mflat_turb
   !----- 4. The right Nusselt number is the largest. -------------------------------------!
   nusselt         = max(nusselt_lami,nusselt_turb)
   !----- 5. The conductance is given by MU08 - equation 10.4 -----------------------------!
   free_gbh_mos    = th_diff * nusselt / lwidth
   !---------------------------------------------------------------------------------------!




   !---------------------------------------------------------------------------------------!
   !     The heat conductance for the thermodynamic budget is the sum of conductances,     !
   ! because we assume both forms of convection happen parallelly.  The conversion from    !
   ! heat to water conductance (in m/s) can be found in L95, page 1198, after equation E5. !
   ! For the ED purposes, the output variables are converted to the units of entropy and   !
   ! water fluxes [J/K/m�/s and kg/m�/s, respectively].                                    !
   !---------------------------------------------------------------------------------------!
   gbh_mos = free_gbh_mos + forced_gbh_mos
   gbh     =             gbh_mos * can_rhos * can_cp
   gbw     = gbh_2_gbw * gbh_mos * can_rhos
   !---------------------------------------------------------------------------------------!

   return
end subroutine leaf3_aerodynamic_conductances
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!      This sub-routine copies some atmospheric fields from the 2-D arrays to the common   !
! module variable.                                                                         !
!------------------------------------------------------------------------------------------!
subroutine leaf3_atmo1d(m2,m3,i,j,thp,theta,rv,rtp,co2p,up,vp,pitot,dens,height            &
                       ,pcpg,qpcpg,dpcpg)
   use leaf_coms , only : ubmin        & ! intent(in)
                        , atm_up       & ! intent(out)
                        , atm_vp       & ! intent(out)
                        , atm_thil     & ! intent(out)
                        , atm_theta    & ! intent(out)
                        , atm_rvap     & ! intent(out)
                        , atm_rtot     & ! intent(out)
                        , atm_shv      & ! intent(out)
                        , geoht        & ! intent(out)
                        , atm_exner    & ! intent(out)
                        , atm_co2      & ! intent(out)
                        , atm_prss     & ! intent(out)
                        , atm_rhos     & ! intent(out)
                        , atm_vels     & ! intent(out)
                        , atm_temp     & ! intent(out)
                        , atm_theiv    & ! intent(out)
                        , atm_vpdef    & ! intent(out)
                        , pcpgl        & ! intent(out)
                        , qpcpgl       & ! intent(out)
                        , dpcpgl       ! ! intent(out)
   use rconstants, only : srtwo        ! ! intent(in)
   use therm_lib , only : thetaeiv     & ! function
                        , vpdefil      & ! function
                        , exner2press  & ! function
                        , extheta2temp ! ! function

   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                  , intent(in) :: m2
   integer                  , intent(in) :: m3
   integer                  , intent(in) :: i
   integer                  , intent(in) :: j
   real   , dimension(m2,m3), intent(in) :: thp
   real   , dimension(m2,m3), intent(in) :: theta
   real   , dimension(m2,m3), intent(in) :: rv
   real   , dimension(m2,m3), intent(in) :: rtp
   real   , dimension(m2,m3), intent(in) :: co2p
   real   , dimension(m2,m3), intent(in) :: up
   real   , dimension(m2,m3), intent(in) :: vp
   real   , dimension(m2,m3), intent(in) :: pitot
   real   , dimension(m2,m3), intent(in) :: dens
   real   , dimension(m2,m3), intent(in) :: height
   real   , dimension(m2,m3), intent(in) :: pcpg
   real   , dimension(m2,m3), intent(in) :: qpcpg
   real   , dimension(m2,m3), intent(in) :: dpcpg
   !----- Local variables. ----------------------------------------------------------------!
   real                                  :: wfact
   real                                  :: vels_1st
   real                                  :: tmp
   !---------------------------------------------------------------------------------------!


   !----- Find the wind speed and make sure it is above a minimum. ------------------------!
   vels_1st     = sqrt(up(i,j)*up(i,j) + vp(i,j)*vp(i,j))
   if (vels_1st == 0.0) then
      atm_vels  = ubmin
      atm_up    = 0.5 * srtwo * ubmin
      atm_vp    = atm_up
   else
      wfact     = max(1.0, ubmin / vels_1st)
      atm_vels  = vels_1st * wfact
      atm_up    = up(i,j)  * wfact
      atm_vp    = vp(i,j)  * wfact
   end if
   !---------------------------------------------------------------------------------------!


   !----- Copy the other values stored at the 2-D arrays to the leaf common. --------------!
   atm_thil     = thp(i,j)
   atm_theta    = theta(i,j)
   atm_rvap     = rv(i,j)
   atm_rtot     = rtp(i,j)
   atm_shv      = atm_rvap / (1. + atm_rvap)
   geoht        = height(i,j)
   atm_exner    = pitot(i,j)
   atm_co2      = co2p(i,j)
   atm_prss     = exner2press(atm_exner)
   atm_temp     = extheta2temp(atm_exner,atm_theta)
   atm_theiv    = thetaeiv(atm_thil,atm_prss,atm_temp,atm_rvap,atm_rtot)
   atm_vpdef    = vpdefil(atm_prss,atm_temp,atm_shv,.true.)
   pcpgl        = pcpg(i,j)
   qpcpgl       = qpcpg(i,j)
   dpcpgl       = dpcpg(i,j)
   !---------------------------------------------------------------------------------------!

   return
end subroutine leaf3_atmo1d
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!      This sub-routine assigns various canopy air space variables for the case in which   !
! leaf is not solved.                                                                      !
!------------------------------------------------------------------------------------------!
subroutine leaf0(m2,m3,mpat,i,j,can_theta,can_rvap,can_co2,can_prss,can_theiv,can_vpdef    &
                ,patch_area)
   use mem_leaf  , only : dthcon         & ! intent(in)
                        , drtcon         & ! intent(in)
                        , pctlcon        ! ! intent(in)
   use leaf_coms , only : atm_theta      & ! intent(in)
                        , atm_rvap       & ! intent(in)
                        , atm_co2        & ! intent(in)
                        , atm_prss       & ! intent(in)
                        , atm_shv        & ! intent(in)
                        , geoht          & ! intent(in)
                        , min_patch_area & ! intent(in)
                        , can_depth_min  & ! intent(in)
                        , can_shv        & ! intent(out)
                        , can_rsat       & ! intent(out)
                        , can_rhv        & ! intent(out)
                        , can_exner      & ! intent(out)
                        , can_temp       & ! intent(out)
                        , can_enthalpy   & ! intent(out)
                        , can_rhos       & ! intent(out)
                        , can_cp         ! ! intent(out)
   use rconstants, only : ep             & ! intent(in)
                        , cpdry          & ! intent(in)
                        , cph2o          ! ! intent(in)
   use therm_lib , only : thetaeiv       & ! function
                        , vpdefil        & ! function
                        , rslif          & ! function
                        , reducedpress   & ! function
                        , idealdenssh    & ! function
                        , press2exner    & ! function
                        , extheta2temp   & ! function
                        , tq2enthalpy    ! ! function

   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                       , intent(in)    :: m2
   integer                       , intent(in)    :: m3
   integer                       , intent(in)    :: mpat
   integer                       , intent(in)    :: i
   integer                       , intent(in)    :: j
   real   , dimension(m2,m3,mpat), intent(inout) :: can_theta
   real   , dimension(m2,m3,mpat), intent(inout) :: can_rvap
   real   , dimension(m2,m3,mpat), intent(inout) :: can_co2
   real   , dimension(m2,m3,mpat), intent(inout) :: can_prss
   real   , dimension(m2,m3,mpat), intent(inout) :: can_theiv
   real   , dimension(m2,m3,mpat), intent(inout) :: can_vpdef
   real   , dimension(m2,m3,mpat), intent(inout) :: patch_area
   !---------------------------------------------------------------------------------------!



   !----- Fill the canopy properties. -----------------------------------------------------!
   can_theta(i,j,2)  = atm_theta - dthcon
   can_rvap(i,j,2)   = atm_rvap  - drtcon
   can_co2(i,j,2)    = atm_co2

   can_shv           = can_rvap(i,j,2) / (1. + can_rvap(i,j,2))
   
   can_prss(i,j,2)   = reducedpress(atm_prss,atm_theta,atm_shv,geoht,can_theta(i,j,2)      &
                                   ,can_shv,can_depth_min)

   can_exner         = press2exner(can_prss(i,j,2))
   can_temp          = extheta2temp(can_exner,can_theta(i,j,2))

   can_rsat          = rslif(can_prss(i,j,2),can_temp)

   can_rhv           = can_rvap(i,j,2) * (ep + can_rsat)                                   &
                     / ( can_rsat * (ep + can_rvap(i,j,2)))

   can_theiv(i,j,2)  = thetaeiv(can_theta(i,j,2),can_prss(i,j,2),can_temp,can_rvap(i,j,2)  &
                               ,can_rvap(i,j,2))

   can_vpdef(i,j,2)  = vpdefil(can_prss(i,j,2),can_temp,can_shv,.true.)

   can_enthalpy      = tq2enthalpy(can_temp,can_shv,.true.)
   can_rhos          = idealdenssh(can_prss(i,j,2),can_temp,can_shv)
   can_cp            = (1.0 - can_shv) * cpdry + can_shv * cph2o
   !---------------------------------------------------------------------------------------!



   !----- Impose area to be bounded. ------------------------------------------------------!
   patch_area(i,j,1) = min(1.0,max(min_patch_area,1.0-pctlcon))
   patch_area(i,j,2) = 1.0 - patch_area(i,j,1)
   !---------------------------------------------------------------------------------------!


   return
end subroutine leaf0
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This sub-routine computes the roughness for a given patch.                           !
!------------------------------------------------------------------------------------------!
subroutine leaf3_roughness(ip,veg_fracarea,patch_area,ustar,topzo,veg_rough,soil_rough     &
                          ,patch_rough)
   use mem_leaf , only : isfcl          ! ! intent(in)
   use leaf_coms, only : min_patch_area & ! intent(in)
                       , z0fac_water    & ! intent(in)
                       , min_waterrough & ! intent(in)
                       , snowfac        & ! intent(in)
                       , snowrough      ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer, intent(in)  :: ip
   real   , intent(in)  :: veg_fracarea
   real   , intent(in)  :: patch_area
   real   , intent(in)  :: ustar
   real   , intent(in)  :: topzo
   real   , intent(in)  :: veg_rough
   real   , intent(in)  :: soil_rough
   real   , intent(out) :: patch_rough
   !----- Local variables. ----------------------------------------------------------------!
   real                 :: summer_rough
   !---------------------------------------------------------------------------------------!


   if (ip == 1) then
      !------------------------------------------------------------------------------------!
      !    For water surfaces (patch 1), compute roughness length based on previous ustar. !
      !------------------------------------------------------------------------------------!
      patch_rough = max(z0fac_water * ustar ** 2, min_waterrough)
   elseif (isfcl >= 1) then
      !----- Possibly land, and with sufficient area. -------------------------------------!
      summer_rough = max( topzo                                                            &
                        , veg_rough * veg_fracarea + soil_rough * (1.0 - veg_fracarea) )
      patch_rough  = summer_rough * (1. - snowfac) + snowrough * snowfac
   else
      !----- This is just to dump something in the roughness, not really used. ------------!
      patch_rough  = snowrough
   end if

   return
end subroutine leaf3_roughness
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This sub-routine normalises the accumulated fluxes and albedo seen by atmosphere     !
! over one full BRAMS timestep (dtlt).                                                     !
!------------------------------------------------------------------------------------------!
subroutine normal_accfluxes(m2,m3,mpat,ia,iz,ja,jz,atm_rhos,patch_area,sflux_u,sflux_v     &
                           ,sflux_w,sflux_t,sflux_r,sflux_c,albedt,rlongup)
   use leaf_coms  , only : dtll_factor    & ! intent(in)
                         , min_patch_area ! ! intent(in)
   use mem_radiate, only : iswrtyp        & ! intent(in)
                         , ilwrtyp        ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                       , intent(in)    :: m2
   integer                       , intent(in)    :: m3
   integer                       , intent(in)    :: mpat
   integer                       , intent(in)    :: ia
   integer                       , intent(in)    :: iz
   integer                       , intent(in)    :: ja
   integer                       , intent(in)    :: jz
   real   , dimension(m2,m3)     , intent(in)    :: atm_rhos
   real   , dimension(m2,m3,mpat), intent(in)    :: patch_area
   real   , dimension(m2,m3)     , intent(inout) :: sflux_u
   real   , dimension(m2,m3)     , intent(inout) :: sflux_v
   real   , dimension(m2,m3)     , intent(inout) :: sflux_w
   real   , dimension(m2,m3)     , intent(inout) :: sflux_t
   real   , dimension(m2,m3)     , intent(inout) :: sflux_r
   real   , dimension(m2,m3)     , intent(inout) :: sflux_c
   real   , dimension(m2,m3)     , intent(inout) :: albedt
   real   , dimension(m2,m3)     , intent(inout) :: rlongup
   !----- Local variables. ----------------------------------------------------------------!
   integer                                       :: i
   integer                                       :: j
   integer                                       :: p
   real                                          :: rho_dtlt
   real                                          :: solarea
   real                                          :: solarea_i
   logical                                       :: rad_on
   !---------------------------------------------------------------------------------------!


   !----- Save the check in a logical variable to speed up the loops. ---------------------!
   rad_on = iswrtyp > 0 .or. ilwrtyp > 0
   !---------------------------------------------------------------------------------------!


   !----- Horizontal loops. ---------------------------------------------------------------!
   latloop: do j=ja,jz
      lonloop: do i=ia,iz

         solarea = patch_area(i,j,1)
         do p=2,mpat
            if (patch_area(i,j,p) >= min_patch_area) solarea = solarea + patch_area(i,j,p)
         end do
         solarea_i = 1.0 / solarea

         rho_dtlt = atm_rhos(i,j) * dtll_factor

         sflux_u(i,j) = sflux_u(i,j) * rho_dtlt * solarea_i
         sflux_v(i,j) = sflux_v(i,j) * rho_dtlt * solarea_i
         sflux_w(i,j) = sflux_w(i,j) * rho_dtlt * solarea_i
         sflux_t(i,j) = sflux_t(i,j) * rho_dtlt * solarea_i
         sflux_r(i,j) = sflux_r(i,j) * rho_dtlt * solarea_i
         sflux_c(i,j) = sflux_c(i,j) * rho_dtlt * solarea_i

          if (rad_on) then
             albedt (i,j) = albedt (i,j) * dtll_factor * solarea_i
             rlongup(i,j) = rlongup(i,j) * dtll_factor * solarea_i
          end if

      end do lonloop
   end do latloop
   !---------------------------------------------------------------------------------------!

   return
end subroutine normal_accfluxes
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This sub-routine decides whether this patch should be solved or not.                 !
!------------------------------------------------------------------------------------------!
subroutine leaf3_solve_veg(ip,mzs,leaf_class,soil_rough,patch_area,veg_fracarea,veg_tai    &
                          ,sfcwater_nlev,sfcwater_mass,sfcwater_depth,initial)
   use leaf_coms , only : min_patch_area    & ! intent(in)
                        , min_sfcwater_mass & ! intent(in)
                        , tai_max           & ! intent(in)
                        , tai_min           & ! intent(in)
                        , snowfac_max       & ! intent(in)
                        , ny07_eq04_a       & ! intent(in)
                        , ny07_eq04_m       & ! intent(in)
                        , snowfac           & ! intent(inout)
                        , resolvable        ! ! intent(inout)
   use rconstants, only : wdns              & ! intent(in)
                        , fsdns             & ! intent(in)
                        , fsdnsi            ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                , intent(in) :: ip
   integer                , intent(in) :: mzs
   real                   , intent(in) :: leaf_class
   real                   , intent(in) :: soil_rough
   real                   , intent(in) :: patch_area
   real                   , intent(in) :: veg_fracarea
   real                   , intent(in) :: veg_tai
   real                   , intent(in) :: sfcwater_nlev
   real   , dimension(mzs), intent(in) :: sfcwater_mass
   real   , dimension(mzs), intent(in) :: sfcwater_depth
   logical                , intent(in) :: initial
   !----- Local variables. ----------------------------------------------------------------!
   integer                             :: nveg
   integer                             :: k
   integer                             :: ksn
   real                                :: total_sfcw_depth
   real                                :: total_sfcw_mass
   real                                :: bulk_sfcw_dens
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     Find the fraction of the canopy covered in snow.  I could not find any            !
   ! reference for the original method (commented out), so I implemented the method used   !
   ! in CLM-4, which is based on:                                                          !
   !                                                                                       !
   ! Niu, G.-Y., and Z.-L. Yang (2007), An observation-based formulation of snow cover     !
   !    fraction and its evaluation over large North American river basins,                !
   !    J. Geophys. Res., 112, D21101, doi:10.1029/2007JD008674                            !
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !     Find the area covered by snow.  This should be done every time.                   !
   !---------------------------------------------------------------------------------------!
   ksn     = nint(sfcwater_nlev)
   total_sfcw_depth = 0.0
   total_sfcw_mass  = 0.0
   do k=1,ksn
      total_sfcw_depth = total_sfcw_depth + sfcwater_depth(k)
      total_sfcw_mass  = total_sfcw_mass  + sfcwater_mass (k)
   end do
   if (total_sfcw_mass > min_sfcwater_mass) then
      bulk_sfcw_dens = max( fsdns, min( wdns, total_sfcw_mass / total_sfcw_depth))
      snowfac        = max( 0.0, min( 0.99                                                 &
                              , tanh( total_sfcw_depth                                     &
                                    / ( ny07_eq04_a * max(0.001,soil_rough)                &
                                      * (bulk_sfcw_dens * fsdnsi) ** ny07_eq04_m ) ) ) )
   else
      snowfac = 0.0
   end if
   ! snowfac = min(.99, total_sfcw_depth / max(.001,veg_height))
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     Now we must check whether this is the initial call or just an update.             !
   !---------------------------------------------------------------------------------------!
   if (initial) then
      !---- First call.  Decide whether the vegetation can be solved. ---------------------!
      if (ip == 1) then
         resolvable = .false.
      else
         nveg = nint(leaf_class)
         resolvable = tai_max(nveg)            >= tai_min .and.                            &
                      veg_tai * (1. - snowfac) >= tai_min
      end if
   elseif (resolvable) then
      !------------------------------------------------------------------------------------!
      !     Call in the middle of the step.  This can go only from resolvable to non-      !
      ! resolvable, in case snow or water has buried or drowned the plants.  The single    !
      ! direction is to avoid calling vegetation properties that cannot start to be        !
      ! computed in the middle of the step.                                                !
      !------------------------------------------------------------------------------------!
      nveg       = nint(leaf_class)
      resolvable = tai_max(nveg)            >= tai_min .and.                               &
                   veg_tai * (1. - snowfac) >= tai_min
   end if
   !---------------------------------------------------------------------------------------!

   return
end subroutine leaf3_solve_veg
!==========================================================================================!
!==========================================================================================!





!==========================================================================================!
!==========================================================================================!
!     This sub-routine updates the 10-day running average of the relative soil potential   !
! for phenology in the next time step.                                                     !
!------------------------------------------------------------------------------------------!
subroutine update_psibar(m2,m3,mzg,npat,ia,iz,ja,jz,dtime,soil_energy,soil_water,soil_text &
                        ,leaf_class,psibar_10d)
   use therm_lib , only : uextcm2tl ! ! subroutine
   use mem_leaf  , only : slz       & ! intent(in)
                        , dtleaf    ! ! intent(in)
   use leaf_coms , only : slzt      & ! intent(in)
                        , slmsts    & ! intent(in)
                        , slpots    & ! intent(in)
                        , slbs      & ! intent(in)
                        , slcpd     & ! intent(in)
                        , kroot     & ! intent(in)
                        , psild     & ! intent(in)
                        , psiwp     ! ! intent(in)
   use rconstants, only : wdns      & ! intent(in)
                        , day_sec   ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   integer                           , intent(in)    :: m2
   integer                           , intent(in)    :: m3
   integer                           , intent(in)    :: mzg
   integer                           , intent(in)    :: npat
   integer                           , intent(in)    :: ia
   integer                           , intent(in)    :: iz
   integer                           , intent(in)    :: ja
   integer                           , intent(in)    :: jz
   real                              , intent(in)    :: dtime
   real   , dimension(mzg,m2,m3,npat), intent(in)    :: soil_energy
   real   , dimension(mzg,m2,m3,npat), intent(in)    :: soil_water
   real   , dimension(mzg,m2,m3,npat), intent(in)    :: soil_text
   real   , dimension    (m2,m3,npat), intent(in)    :: leaf_class
   real   , dimension    (m2,m3,npat), intent(inout) :: psibar_10d
   !----- Local variables. ----------------------------------------------------------------!
   integer                                           :: i
   integer                                           :: j
   integer                                           :: k
   integer                                           :: ip
   integer                                           :: nsoil
   integer                                           :: nveg
   real                                              :: available_water
   real                                              :: psi_layer
   real                                              :: wgpfrac
   real                                              :: soil_temp
   real                                              :: soil_fliq
   real                                              :: weight
   !---------------------------------------------------------------------------------------!


   !----- Find the weight. ----------------------------------------------------------------!
   weight = min(dtime,dtleaf) / (10. * day_sec)
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !    Loop over all points, but skip water patches.                                      !
   !---------------------------------------------------------------------------------------!
   yloop: do j=ja,jz
      xloop: do i=ia,iz
         patchloop: do ip=2,npat
            nveg = nint(leaf_class(i,j,ip))
            available_water = 0.0
            do k = kroot(nveg),mzg
               nsoil = nint(soil_text(k,i,j,ip))

               if (nsoil /= 13) then
                  !----- Find the liquid fraction, which will scale available water. ------!
                  call uextcm2tl(soil_energy(k,i,j,ip),soil_water(k,i,j,ip)*wdns           &
                                ,slcpd(nsoil),soil_temp,soil_fliq)
                  !------------------------------------------------------------------------!



                  !----- Find the water potential of this layer. --------------------------!
                  wgpfrac         = min(soil_water(k,i,j,ip)/slmsts(nsoil), 1.0)
                  psi_layer       = slzt(k) + slpots(nsoil) / wgpfrac ** slbs(nsoil)
                  !------------------------------------------------------------------------!



                  !----- Add the contribution of this layer, based on the potential. ------!
                  available_water = available_water                                        &
                                  + max(0., (psi_layer    - psiwp(nsoil))                  &
                                          / (psild(nsoil) - psiwp(nsoil)) )                &
                                  * soil_fliq * (slz(k+1)-slz(k))
                  !------------------------------------------------------------------------!
               end if
               !---------------------------------------------------------------------------!
            end do
            !------------------------------------------------------------------------------!



            !----- Normalise the available water. -----------------------------------------!
            available_water      = available_water / abs(slz(kroot(nveg)))
            !------------------------------------------------------------------------------!



            !----- Move the moving average. -----------------------------------------------!
            psibar_10d(i,j,ip) = available_water    * weight                               &
                               + psibar_10d(i,j,ip) * (1.0 - weight)
            !------------------------------------------------------------------------------!

         end do patchloop
      end do xloop
   end do yloop
   !---------------------------------------------------------------------------------------!

   return
end subroutine update_psibar
!==========================================================================================!
!==========================================================================================!
