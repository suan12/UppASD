!-------------------------------------------------------------------------------
! MODULE: SpinTorques
!> @brief Routines for calculating \f$\frac{\partial\mathbf{m}}{\partial\mathbf{r}}\f$. Needed for generalized spin-torque term \f$\left(\mathbf{m} \times \left(\mathbf{m} \times \frac{\partial\mathbf{m}}{\partial \mathbf{r}}\right)\right)\f$
!> @details For calculating the spin transfer torques, we use the standard adiabatic and non-adiabatic terms as introduced in the LLG equation by Zhang & Li. PRL 93, 127204 (2004).
!> The terms are rewritten to suit the LL equations used in UppASD and here we use the same formulas as Schieback et. al, Eur. Phys. J. B 59, 429, (2007)
!> Currently the torques are only calculated as their respective fields (i.e. missing the preceeding \f$\mathbf{m} \times\f$) since that is taken care of in the Depondt solver
!> @author
!> Anders Bergman
!> @notes
!> J. Chico
!> - Added the SHE torque and the calculation of the current density
!> @copyright
!! Copyright (C) 2008-2018 UppASD group
!! This file is distributed under the terms of the
!! GNU General Public License.
!! See http://www.gnu.org/copyleft/gpl.txt
!-------------------------------------------------------------------------------

module SpinTorques

   use Parameters
   use Profiling

   implicit none

   !Spin-transfer torque inputs
   character(len=1) :: STT       !< Treat spin transfer torque? (Y/N)
   character(len=1) :: jsite     !< Treat site dependent jvec
   character(len=1) :: do_she    !< Treat SHE spin transfer torque
   character(len=35) :: jvecfile !< File name for the site dependent jvec
   real(dblprec) :: adibeta      !< Adiabacity parameter for STT
   real(dblprec) :: spin_pol     !< Spin polarization
   real(dblprec) :: SHE_angle    !< Spin Hall angle
   real(dblprec) :: thick_ferro  !< Thickness of ferromagnetic layer (t_f/alat)
   real(dblprec), dimension(3) :: jvec !< Spin current vector
   real(dblprec), dimension(:,:), allocatable :: sitenatomjvec !< Site dependent spin current vector

   !Spin-transfer torque data arrays
   real(dblprec), dimension(:,:,:), allocatable :: btorque !< Spin transfer torque
   real(dblprec), dimension(:,:,:), allocatable :: dmomdr  !< Current magnetic moment vector
   real(dblprec), dimension(:,:,:), allocatable :: she_btorque !< SHE spin transfer torque
   real(dblprec), dimension(:), allocatable  :: stt_prefac !< Prefactor for the STT


   public

contains

   !---------------------------------------------------------------------------
   !> @brief
   !> Wrapper for the actual calculation of the spin torques
   !
   !> @author
   !> Anders Bergman
   !---------------------------------------------------------------------------
   subroutine calculate_spintorques(Natom, Mensemble,lambda1_array,emom,mmom)
      !
      use Gradients, only : differentiate_moments
      !
      implicit none
      !
      !.. Input variables
      integer, intent(in) :: Natom !< Number of atoms in system
      integer, intent(in) :: Mensemble !< Number of ensembles
      real(dblprec), dimension(Natom), intent(in) :: lambda1_array !< Damping parameter
      real(dblprec), dimension(3,Natom, Mensemble), intent(in) :: emom  !< Current magnetic moment vector$
      real(dblprec), dimension(Natom, Mensemble), intent(in) :: mmom  !< Current magnetic moment vector$
      !
      ! .. Local variables
      integer :: j, k
      !
      if(stt=='A') then
         call differentiate_moments(Natom, Mensemble,emom, dmomdr, sitenatomjvec)
         !$omp parallel do default(shared) private(j,k)
         do j=1, Natom
            do k=1, Mensemble
               btorque(1,j,k)=(lambda1_array(j)-adibeta)*dmomdr(1,j,k)
               btorque(2,j,k)=(lambda1_array(j)-adibeta)*dmomdr(2,j,k)
               btorque(3,j,k)=(lambda1_array(j)-adibeta)*dmomdr(3,j,k)
               stt_prefac(j)=-(1.0d0+adibeta*lambda1_array(j))
            enddo
         enddo
         !$omp end parallel do
         ! Calculates the m x (j*d/dr) m term
         call mom_cross_dmomdr(Natom, Mensemble,emom)

         ! external_field=external_field+btorque
      else if(stt=='F') then
         call mom_cross_mfixed(Natom, Mensemble,emom)
         ! external_field=external_field+btorque
      end if

      ! Calculates the spin hall effect generated spin transfer torque
      if (do_she=='Y') then
         call SHE_torque(Natom,Mensemble,lambda1_array,emom,mmom)
      endif

   end subroutine calculate_spintorques

   !---------------------------------------------------------------------------
   !> @brief
   !> Calculate \f$\left( \mathbf{m}\times  \left(\mathbf{u}\cdot \frac{\partial}{\partial\mathbf{r}}\right) \mathbf{m} \right)\f$ (which then ends up as one part of the spin transfer torque) for atomic damping dependence
   !
   !> @author
   !> Anders Bergman
   !---------------------------------------------------------------------------
   subroutine mom_cross_dmomdr(Natom, Mensemble,emomM)

      implicit none

      integer, intent(in) :: Natom !< Number of atoms in system
      integer, intent(in) :: Mensemble !< Number of ensembles
      real(dblprec), dimension(3,Natom, Mensemble), intent(in) :: emomM  !< Current magnetic moment vector

      integer :: iatom, k

      !$omp parallel do default(shared) private(iatom,k)
      do iatom=1, Natom
         do k=1, Mensemble
            btorque(1,iatom,k)=btorque(1,iatom,k)+stt_prefac(iatom)*emomM(2,iatom,k)*dmomdr(3,iatom,k) &
               -stt_prefac(iatom)*emomM(3,iatom,k)*dmomdr(2,iatom,k)
            btorque(2,iatom,k)=btorque(2,iatom,k)+stt_prefac(iatom)*emomM(3,iatom,k)*dmomdr(1,iatom,k) &
               -stt_prefac(iatom)*emomM(1,iatom,k)*dmomdr(3,iatom,k)
            btorque(3,iatom,k)=btorque(3,iatom,k)+stt_prefac(iatom)*emomM(1,iatom,k)*dmomdr(2,iatom,k) &
               -stt_prefac(iatom)*emomM(2,iatom,k)*dmomdr(1,iatom,k)
         end do
      end do
      !$omp end parallel do

   end subroutine mom_cross_dmomdr
   !---------------------------------------------------------------------------
   !> @brief
   !> Calculates the spin transfer torque for currents passing through a fixed ferromagnetic layer
   !
   !> @author
   !> Anders Bergman
   !---------------------------------------------------------------------------
   subroutine mom_cross_mfixed(Natom, Mensemble,emomM)

      implicit none

      integer, intent(in) :: Natom !< Number of atoms in system
      integer, intent(in) :: Mensemble !< Number of ensembles
      real(dblprec), dimension(3,Natom, Mensemble), intent(in) :: emomM  !< Current magnetic moment vector

      integer :: iatom, k

      btorque=0.0d0
      do k=1, Mensemble
         do iatom=1, Natom
            btorque(1,iatom,k)=emomM(2,iatom,k)*sitenatomjvec(3,iatom)-emomM(3,iatom,k)*sitenatomjvec(2,iatom)
            btorque(2,iatom,k)=emomM(3,iatom,k)*sitenatomjvec(1,iatom)-emomM(1,iatom,k)*sitenatomjvec(3,iatom)
            btorque(3,iatom,k)=emomM(1,iatom,k)*sitenatomjvec(2,iatom)-emomM(2,iatom,k)*sitenatomjvec(1,iatom)
         end do
      end do

   end subroutine mom_cross_mfixed

   !---------------------------------------------------------------------------$
   !> @brief$
   !> Calculate the SHE torque generated by a current passing through a non magnetic material with SOC$
   !$
   !> @author$
   !> Jonathan Chico$
   !---------------------------------------------------------------------------$

   subroutine SHE_torque(Natom,Mensemble,lambda1_array,emom,mmom)

      implicit none

      ! .. Input variables
      integer, intent(in) :: Natom !< Number of atoms in system
      integer, intent(in) :: Mensemble !< Number of ensembles
      real(dblprec), dimension(Natom), intent(in) :: lambda1_array !< Damping parameter
      real(dblprec), dimension(3,Natom, Mensemble), intent(in) :: emom  !< Current magnetic moment vector$
      real(dblprec), dimension(Natom, Mensemble), intent(in) :: mmom  !< Current magnetic moment vector$

      ! ... Local variables
      integer :: iatom, k
      real(dblprec) :: she_fact

      she_btorque=0.0D0
      ! Factor for the strenght of the spin hall torque
      she_fact=she_angle/(spin_pol*thick_ferro)

      !$omp parallel do default(shared) private(iatom,k)
      do k=1, Mensemble
         do iatom=1, Natom
            she_btorque(1,iatom,k) =-she_fact*sitenatomjvec(1,iatom)*emom(3,iatom,k)-lambda1_array(iatom)*mmom(iatom,k)*sitenatomjvec(2,iatom)
            she_btorque(2,iatom,k) =-she_fact*sitenatomjvec(2,iatom)*emom(3,iatom,k)+lambda1_array(iatom)*mmom(iatom,k)*sitenatomjvec(1,iatom)
            she_btorque(3,iatom,k) = she_fact*sitenatomjvec(2,iatom)*emom(2,iatom,k)+she_fact*sitenatomjvec(1,iatom)*emom(1,iatom,k)
         enddo
      enddo
      !$omp end parallel do

   end subroutine SHE_torque

   !----------------------------------------------------------------------------
   !> @brief
   !> Allocation and deallocation of the arrays for the STT calculation
   !
   !> @author
   !> Jonathan Chico
   !----------------------------------------------------------------------------
   subroutine allocate_stt_data(Natom,Mensemble,flag)

      implicit none

      integer, intent(in) :: flag
      integer, intent(in) :: Natom
      integer, intent(in) :: Mensemble

      integer :: i_stat, i_all

      if (flag==1) then
         ! Allocate the SHE torque field
         if (do_she=='Y') then
            allocate(she_btorque(3,Natom,Mensemble),stat=i_stat)
            call memocc(i_stat,product(shape(she_btorque))*kind(she_btorque),'she_btorque','allocate_stt_data')
            she_btorque=0.0D0
         endif

         if (stt=='A') then
            allocate(stt_prefac(Natom),stat=i_stat)
            call memocc(i_stat,product(shape(stt_prefac))*kind(stt_prefac),'stt_prefac','allocate_stt_sata')
            stt_prefac=0.0D0
            allocate(btorque(3,Natom,Mensemble),stat=i_stat)
            call memocc(i_stat,product(shape(btorque))*kind(btorque),'btorque','allocate_stt_data')
            btorque=0.0D0
            allocate(dmomdr(3,Natom,Mensemble),stat=i_stat)
            call memocc(i_stat,product(shape(dmomdr))*kind(dmomdr),'dmomdr','allocate_stt_data')
            dmomdr=0.0D0
         else if (stt=='F') then
            allocate(btorque(3,Natom,Mensemble),stat=i_stat)
            call memocc(i_stat,product(shape(btorque))*kind(btorque),'btorque','allocate_stt_data')
            btorque=0.0D0
         endif

      else

         if (do_she=='Y') then
            i_all=-product(shape(she_btorque))*kind(she_btorque)
            deallocate(she_btorque,stat=i_stat)
            call memocc(i_stat,i_all,'btorque','allocate_stt_data')
         endif

         if (stt=='A') then
            i_all=-product(shape(stt_prefac))*kind(stt_prefac)
            deallocate(stt_prefac,stat=i_stat)
            call memocc(i_stat,i_all,'stt_prefac','allocate_stt,data')
            i_all=-product(shape(btorque))*kind(btorque)
            deallocate(btorque,stat=i_stat)
            call memocc(i_stat,i_all,'btorque','allocate_stt_data')
            i_all=-product(shape(dmomdr))*kind(dmomdr)
            deallocate(dmomdr,stat=i_stat)
            call memocc(i_stat,i_all,'dmomdr','allocate_stt_data')
         else if(stt=='F') then
            i_all=-product(shape(btorque))*kind(btorque)
            deallocate(btorque,stat=i_stat)
            call memocc(i_stat,i_all,'btorque','allocate_stt_data')
         endif

      endif

   end subroutine allocate_stt_data


   !---------------------------------------------------------------------------
   !> @brief
   !> Read input parameters.
   !
   !> @author
   !> Anders Bergman
   !---------------------------------------------------------------------------
   subroutine read_parameters_stt(ifile)
      use FileParser

      implicit none

      ! ... Formal Arguments ...
      integer, intent(in) :: ifile   !< File to read from
      !
      ! ... Local Variables ...
      character(len=50) :: keyword,cache
      integer :: rd_len, i_err, i_errb
      logical :: comment



      do
         10     continue
         ! Read file character for character until first whitespace
         keyword=""
         call bytereader(keyword,rd_len,ifile,i_errb)

         ! converting Capital letters
         call caps2small(keyword)

         ! check for comment markers (currently % and #)
         comment=(scan(trim(keyword),'%')==1).or.(scan(trim(keyword),'#')==1).or.&
            (scan(trim(keyword),'*')==1).or.(scan(trim(keyword),'=')==1.or.&
            (scan(trim(keyword),'!')==1))

         if (comment) then
            read(ifile,*)
         else
            ! Parse keyword
            keyword=trim(keyword)
            select case(keyword)

            case('stt')
               read(ifile,*,iostat=i_err) stt
               if(i_err/=0) write(*,*) 'ERROR: Reading ',trim(keyword),' data',i_err

            case('jvec')
               read(ifile,*,iostat=i_err) jvec
               if(i_err/=0) write(*,*) 'ERROR: Reading ',trim(keyword),' data',i_err

            case('jsite')
               read(ifile,*,iostat=i_err) jsite
               if(i_err/=0) write(*,*) 'ERROR: Reading ',trim(keyword),' data',i_err

            case('jvecfile')
               read(ifile,'(a)',iostat=i_err) cache
               if(i_err/=0) write(*,*) 'ERROR: Reading ',trim(keyword),' data',i_err
               jvecfile=adjustl(trim(cache))

            case('adibeta')
               read(ifile,*,iostat=i_err) adibeta
               if(i_err/=0) write(*,*) 'ERROR: Reading ',trim(keyword),' data',i_err

            case('do_she') ! Consider the SHE generated torque
               read(ifile,*,iostat=i_err) do_she
               if(i_err/=0) write(*,*) 'ERROR: Reading ',trim(keyword),' data',i_err

            case('spin_pol') ! Spin polarization
               read(ifile,*,iostat=i_err) spin_pol
               if(i_err/=0) write(*,*) 'ERROR; Reading ',trim(keyword),' data',i_err

            case('she_angle') ! Spin Hall Angle
               read(ifile,*,iostat=i_err) she_angle
               if(i_err/=0) write(*,*) 'ERROR: Reading ',trim(keyword),' data',i_err

            case('thick_ferro') ! Thickness of the ferromagnetic layer
               read(ifile,*,iostat=i_err) thick_ferro
               if(i_err/=0) write(*,*) 'ERROR: Reading ', trim(keyword),' data',i_err

            end select
         end if

         ! End of file
         if (i_errb==20) goto 20
         ! End of row
         if (i_errb==10) goto 10
      end do

      20  continue

      rewind(ifile)
      return
   end subroutine read_parameters_stt

   !-----------------------------------------------------------------------------
   ! SUBROUTINE: init_stt
   !> @brief Set default values for STT calculations
   !-----------------------------------------------------------------------------
   subroutine init_stt()
      !
      implicit none


      !Spin transfer torque
      STT         = "N"
      jsite       = "N"
      do_she      = "N"
      adibeta     = 0.0d0
      spin_pol    = 0.0D0
      jvecfile    = 'jvecfile'
      she_angle   = 0.0D0
      thick_ferro = 0.0D0

   end subroutine init_stt

   !---------------------------------------------------------------------------
   !> @brief
   !> Read site dependent currents
   !
   !> @author
   !> Jonathan Chico, Anders Bergman
   !>
   !---------------------------------------------------------------------------
   subroutine read_jvecfile(Natom)

      integer, intent(in) :: Natom

      integer :: i,flines, isite, i_stat

      allocate(sitenatomjvec(3,Natom),stat=i_stat)
      call memocc(i_stat,product(shape(sitenatomjvec))*kind(sitenatomjvec),'sitenatomjvec','read_jvecfile')

      if (jsite=='Y') then

         open(ifileno, file=trim(jvecfile))

         flines=0
         ! Pre-read file to get number of lines
         do
            read(ifileno,*,end=200)  isite
            flines=flines+1
         end do

         200 continue

         rewind(ifileno)

         write(*,'(2x,a)') 'Reading site dependent currents'

         ! If the size of the file is NATOM then there is no problem
         if ( Natom.eq.flines ) then

            do i=1, flines
               read(ifileno,*) isite, sitenatomjvec(1,isite), sitenatomjvec(2,isite), sitenatomjvec(3,isite)
            end do
         else
            write(*,*) 'WARNING: Size of the SITEATOMJVEC is not NATOM'
            do i=1, flines
               read(ifileno,*) isite, sitenatomjvec(1,isite), sitenatomjvec(2,isite), sitenatomjvec(3,isite)
            end do

         end if

         close(ifileno)

         ! If there is no site dependent current set it to be constant
      else
         do i=1, Natom
            sitenatomjvec(1,i)=jvec(1)
            sitenatomjvec(2,i)=jvec(2)
            sitenatomjvec(3,i)=jvec(3)
         enddo
      endif

   end subroutine read_jvecfile

   !---------------------------------------------------------------------------
   !> @brief
   !> Calculation of the current density in A/m^2
   !
   !> @author
   !> Jonathan Chico
   !---------------------------------------------------------------------------
   subroutine print_curr_density(NA,Nchmax,conf_num,alat,spin_pol,C1,C2,C3,jvec,ammom_inp)

      use Constants

      implicit none

      ! .. Input variables
      integer, intent(in) :: NA  !< Number of atoms in one cell
      integer, intent(in) :: Nchmax !< Max number of chemical components on each site in cell
      integer, intent(in) :: conf_num !< Number of LSF configurations
      real(dblprec), intent(inout) :: alat !< Lattice parameter
      real(dblprec), intent(inout) :: spin_pol  !< Spin polarization of the current
      real(dblprec), dimension(3), intent(in) :: C1 !< First lattice vector
      real(dblprec), dimension(3), intent(in) :: C2 !< Second lattice vector
      real(dblprec), dimension(3), intent(in) :: C3 !< Third lattice vector
      real(dblprec), dimension(3), intent(in) :: jvec !< Input spin polarized current
      real(dblprec), dimension(NA,Nchmax,conf_num), intent(in) :: ammom_inp !< Magnetic moment directions from input (for alloys)

      ! .. Local variables
      real(dblprec) :: cell_vol  !< Volume of the unit cell
      real(dblprec) :: total_mom !< Total magnetization of the unit cell
      real(dblprec), dimension(3) :: curr_den !< Current density in A/m^2

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      ! Calculation of the current density in the sample
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      ! If alat is not defined set it to BCC Fe
      if (alat.eq.1.d0) then
         alat=2.856e-10
         write(*,'(1x,a,2x,G14.6,a)') 'No lattice constant given, assuming BCC Fe lattice constant: ',alat,'m'
      endif

      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      ! Calculate the volume of the cell in meters
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      cell_vol=(C1(1)*C2(2)*C3(3)-C1(1)*C2(3)*C3(2)+&
         C1(2)*C2(3)*C3(1)-C1(2)*C2(1)*C3(3)+&
         C1(3)*C2(1)*C3(2)-C1(3)*C2(2)*C3(1))*alat**3

      total_mom=sum(ammom_inp(:,1,1))

      ! If the spin polarization is not set set it to one
      if (spin_pol.eq.0) then
         spin_pol=1
         write(*,'(1x,a,2x,G14.6)') 'No polarization set, assuming 100%: ',spin_pol
      endif
      ! Calculate the current density
      curr_den(1:3)=ev*total_mom*gama*alat*jvec(1:3)/(cell_vol*spin_pol)
      write(*,'(a)',advance='no') 'Current density vector: '
      write(*,'(2x,G14.6,2x,G14.6,2x,G14.6,1x,a)') curr_den(1),curr_den(2),curr_den(3),'A/m^2'
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      ! End of calculation of the current density in the sample
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   end subroutine print_curr_density

end module SpinTorques
