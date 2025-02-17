!------------------------------------------------------------------------------
!
! read_obs_series.f90 -- Read station time series from a set of BUFR files.
!
! This is a somewhat generic routine to read assembled hourly
! time series from a set of BUFR files.  One call reads time
! series for a single variable, and all available sites within
! the data set.
!
! 2014-jun-05	Original version.  By Dave Allured, NOAA/ESRL/PSD/CIRES.
!		Adapted from read_gridded_vars.f90, version 2014-may-13.
!		For EPA AIRNow BUFR data sets received by NOAA NWS/NCO.
! 2014-jun-06	Adjust for clean progress display at diag level 2.
! 2014-jun-11	Controlled halt if all files missing.
! 2014-jun-12	Caller specifies BUFR var name, not symbolic var name.
! 2014-jun-19	Minor print adjustments and comment fixes.
!
! 2016-feb-10	Reduce coordinate mismatch messages.
!		Add file summary messages for mismatches, diag level 1 and up.
!
! 2017-mar-30	Fix minor bug in internal var table reader.  Enable ozone.
! 2021-nov-08	Fix gfortran 10 pedantic error, internal read from parameter.
!
! Input:   infile_template = path template for input data set.  May include
!		leading environment var, and YYYY MM DD substitution strings.
!          varname = BUFR name for requested data variable.
!	   start_date, end_date = first and last dates of requested time series.
!          Also see secondary input parameters below.
!
! Output:  site_ids = site ID strings.
!	   site_lats, site_lons = site coordinates.
!	   out_data = 2-D array for time series data.  (Time, sites).
!		Contigious hourly time series, no skipped days.
!	   vmiss = missing value code in data.
!	   units = units string for requested variable in the current data set.
!
! Notes:
!
! In a single call, this version reads full time series for one
! variable from multiple input files.  Hourly time series are
! returned in a 2-D array, time x sites.
!
! Output arrays are auto-allocated for all available sites, and
! for the requested time interval.
!
! Missing values are encoded with the original missing value code
! in the data set.  This code is returned in the vmiss output.
!
! No units conversion is performed.  Data are returned in the
! original units as stored in the data set.
!
! Start and end date indexes:  Integer Gregorian dates, relative
! to 1 = January 1 of base_year.  See index_to_date library
! routine for details.
!
! diag:  Set verbosity, i.e. diagnostic messaging level.  The
! messaging level is cumulative.  0 = errors only, 1 = sparse,
! 2 = short progress messages, 3 = output values, 4 = short work
! arrays, 5 = more details.
!
! Error handling:
!
! Single-value soft errors are handled invisibly by a lower layer.
! Console warning messages may be produced for some kinds of
! these errors,  Single-value errors are replaced with missing
! values in the result array.
!
! Missing or invalid files are also treated as soft errors, and
! ignored.  Data for such files is included in the output time
! series as all missing values.
!
! Serious errors may be detected at a lower level, resulting in
! a diagnostic message and program abort.
!
!------------------------------------------------------------------------------

module read__obs_series
contains

subroutine read_obs_series (infile_template, varname, start_date, end_date, &
      base_year, diag, site_ids, site_lats, site_lons, out_data, vmiss, units)

   use config, only : dp
   use expand__filename
   use index_to_date_mod
   use read__bufr_var
   use stdlit, only : normal
   implicit none

! Input arguments.

   character(*), intent(in) :: infile_template	! template for input file paths
   character(*), intent(in) :: varname		! requested BUFR var name
   integer,      intent(in) :: start_date	! starting date index
   integer,      intent(in) :: end_date		! ending date index
   integer,      intent(in) :: base_year	! base year for date indexes
   integer,      intent(in) :: diag		! diag verbosity level, 0-N

! Output arguments.

   character(*), intent(out), allocatable :: site_ids(:)   ! site ID strings (S)
   real(dp),     intent(out), allocatable :: site_lats(:)  ! site coords (S)
   real(dp),     intent(out), allocatable :: site_lons(:)
   real(dp),     intent(out), allocatable :: out_data(:,:) ! time series (T,S)
   real(dp),     intent(out)              :: vmiss	   ! missing value code
   character(*), intent(out)              :: units	   ! units str for var.

! External function definition.

   real distance_btw_coords

! Local program parameters.

   integer, parameter :: max_sites = 3000	! max number of sites
   						!  for temporary arrays

   integer, parameter :: nhours = 24		! hour dimension size

! Limit for discrepancy between coordinates from two different input
! files, for the same site ID.
! This is the actual surface distance between two points on the globe.
! Currently makes only warning messages, when exceeded.

   real, parameter :: max_coordinate_drift = 0.01   ! kilometers

   character(*), parameter :: calendar = 'gregorian'

! Local variables.

   character fmt1*50, infile*200
   character var_symbolic*40, var_bufr*40

   integer i, j, si, si1, si2, nsites, nsites_in
   integer hour, hour_dim, ti1, ti2, day_offset
   integer year, month, day, yfile, mfile, dfile
   integer date_index, ndays, status
   integer ndays_valid, ndays_missing, ndays_error
   integer typo_expect, tphr_expect
   integer all_missing_count
   integer nsites_coord_mismatch, nfiles_coord_mismatch

   real dist, max_mismatch_distance
   logical ex, found

! Dynamic arrays.

   character(len(site_ids)), allocatable :: file_ids(:)
   real(dp), allocatable :: file_lats(:), file_lons(:)
   real(dp), allocatable :: file_data(:,:)

! Local over-dimensioned arrays for site data.  "t" means "temporary" array.

   character(len(site_ids)) tids(max_sites)
   real(dp) tlats(max_sites), tlons(max_sites)
   real(dp), allocatable :: tdata(:,:)		! temp storage, full time series

! Lookup table for known BUFR variables and parameters.
! Last two items are for consistency checks only.

! NOTE, 2014-JUN-12:  Symbolic var names are ignored in this version.
! All internal references are for BUFR names only.

   character(*), parameter :: var_table(2) = &
      !  Symbolic   BUFR       TYPO (type      TPHR (averaging
      !  Var name   Var name   of pollutant)   interval)
      !  --------   --------   -------------   ---------------
      (/ ' pm2.5      COPOPM     11              -1              ', &
         ' ozone      COPO       0               -1              '  /)

   character(len(var_table)) :: var_table2(2) = var_table(:)
   			! gfortran requires pedantic copy for internal read

!-------------------------------------------------
! Initialize.
!-------------------------------------------------

   if (diag >= 2) print *
   if (diag >= 2) print '(a)', &
      '======================================================================='
   if (diag >= 1) print '(a)', 'read_obs_series: Start.'
   if (diag >= 2) print '(2a)','    Requested input variable = ', trim (varname)

   nsites = 0				! empty site arrays

   si2 = 0				! init "previous" site index
   					! needed to suppress possible compiler
                                        ! warning, not needed for lookup algo

   ndays_valid   = 0			! init statistics
   ndays_missing = 0
   ndays_error   = 0

   nfiles_coord_mismatch = 0

! Find requested var in local var table.

   if (diag >= 5) print *, '      Find requested var "' // trim (varname) &
      // '" in local var table.'

   do i = 1, size (var_table)
      read (var_table2(i), *) var_symbolic, var_bufr, typo_expect, tphr_expect

      if (diag >= 5) then
         fmt1 = '(i10,2(3x,a),2(3x,g0.3))'
         print fmt1, i, trim (var_symbolic), trim (var_bufr), typo_expect, &
            tphr_expect
      end if

      if (var_bufr == varname) exit		! found requested var, continue

      if (i >= size (var_table)) then
         print '(3a)', ' *** read_obs_series: Requested variable "', &
            trim (varname), '" is not in local var table.'
         print *, '*** Fix requested var, or update this routine.'
         print *, '*** Fatal error.  Abort.'
         call exit (1)
      end if
   end do

!! OUT 2014-jun-12:
!!   if (diag >= 2) print '(4a)', '    BUFR var name for ', trim (varname), &
!!      ' = ', trim (var_bufr)

! Lookup table for associated unit strings.
! BUFRLIB is currently missing the units capabillity (May 2014).
! Units copied from debufr dumps.
! This is a separate table because some special chars would break
! the simple reader above.

   units = 'unknown'			! default to unknown

   if (var_bufr == 'COPO  ') units = 'MOLE/MOLE'
   if (var_bufr == 'COPOPM') units = 'KG/(M**3)'

! Allocate the time series temporary array.

   ndays    = end_date - start_date + 1
   hour_dim = nhours * ndays

   if (diag >= 3) print *, '  Allocate temporary time series array for' &
      // ' maximum number of sites.'
   if (diag >= 3) print '(a,2(1x,i0))', '   hour_dim, max_sites =', hour_dim, &
      max_sites

   allocate (tdata(hour_dim, max_sites))

!-----------------------------------------------------------
! Main loop over each input file.  One file per day.
!-----------------------------------------------------------

date_loop: &
   do date_index = start_date, end_date

      nsites_coord_mismatch = 0			! clear mismatch statistics
      max_mismatch_distance = 0			! for this file

      day_offset = date_index - start_date	! compute time insertion
      ti1 = 1 + (nhours * day_offset)		! indices for current date
      ti2 = ti1 + nhours - 1

      call index_to_date (date_index, year, month, day, base_year, calendar)
      					! get current Y M D integers

      hour = 99				! not expected in current template

      call expand_filename (infile_template, year, month, day, hour, infile)
      					! make input file name for current date

! Check for file missing for current date.

      inquire (file=infile, exist=ex)

      if (.not. ex) then
         if (diag >= 2) &
            print '(2a)', '  File missing, skipping this date: ', trim (infile)
         ndays_missing = ndays_missing + 1	! count missing input files
         cycle date_loop
      end if

! Explicitly deallocate previous input arrays, as needed.
! Arrays change size between input files.

      if (allocated (file_data)) then
         if (diag >= 5) print *, '   Deallocate previous input arrays.'
         deallocate (file_ids, file_lats, file_lons, file_data)
      end if

! Read input file for this date.

      if (diag >= 4) print *
      if (diag >= 2) print '(2a)', '  Read file: ', trim (infile)

      call read_bufr_var (infile, var_bufr, typo_expect, tphr_expect, &
         max_sites, diag, yfile, mfile, dfile, nsites_in, file_ids, &
         file_lats, file_lons, file_data, vmiss, status)

! If input file is flagged invalid, ignore returned data and skip this date.
! Subroutine prints its own diagnostics.

      if (status /= normal) then
         ndays_error = ndays_error + 1		! count days with input errors
         cycle date_loop
      end if

! Check for invalid date in file.

      if (yfile /= year .or. mfile /= month .or. dfile /= day) then
         print *, '*** read_obs_series: Warning: Date mismatch.'
         print *, '*** Embedded date in file is different than expected date.'
         print '(2a)', ' *** File = ', trim (infile)
         print '(a,i0.4,2(1x,i0.2))', ' *** Date in file  = ', &
            yfile, mfile, dfile
         print '(a,i0.4,2(1x,i0.2))', ' *** Expected date = ', &
            year, month, day
         print *, '*** Current file is rejected.'
         print *
         ndays_error = ndays_error + 1	! count missing input files
         cycle date_loop
      end if

! First time only, clear primary time series array to all missing.
! Was deferred until we had a value for vmiss from first input file.

      if (date_index == start_date) tdata(:,:) = vmiss

!-----------------------------------------------------------
! Copy input site data into primary site arrays.
! Correlate with previous site ID's.
!-----------------------------------------------------------

site_loop: &
      do si1 = 1, nsites_in

! Find the site ID in the current site list.
! si1 = input site index, si2 = site index in primary list.

! This method is optimized to the assumption of similar site ordering
! between input files.  Start searching with the site following the
! previous found site.

! There is no extra penalty when this assumption breaks down.  Either
! way, there will be at most a single pass through the primary site list,
! for each input site.

! On entry each time, si2 = index of previous site, initially.
! Works correctly for startup (nsites = 0), and both known and
! unknown sites.

         found = .false.

         do j = 1, nsites
            si2 = si2 + 1			! advance to next site in list
            if (si2 > nsites) si2 = 1		! wrap around end of list

            found = (tids(si2) == file_ids(si1))
            if (found) exit			! site ID found
         end do

! Site not found.  Check for site array overflow.

         if (.not. found) then

            if (nsites >= max_sites) then
               print *, '*** read_obs_series: Exceeded maximum number of sites.'
               print '(a,i0)', ' *** Current array size = ', max_sites
               print '(2a)',   ' *** Current site ID    = ', trim(file_ids(si1))
               print *, '*** Update program, increase max_sites number.'

! Array overflow, fatal error.
! Comment out the next two lines, if soft error handling is preferred.

               print *, '*** Fatal error.  Abort.'
               call exit (1)

               cycle site_loop			! if enabled: ignore data from
            end if				! this site, treat as soft error

! Insert new site into the primary site array.

            nsites    = nsites + 1		! increase array size
            si2       = nsites			! array index for new site

            tids(si2)  = file_ids(si1)		! add new site ID
            tlats(si2) = file_lats(si1)		! add lat, lon coordinates
            tlons(si2) = file_lons(si1)
         end if

! Now si2 = current site index number.
! Check for possible mismatched coordinates.

         dist = distance_btw_coords (real (file_lats(si1)), &
            real (file_lons(si1)), real (tlats(si2)), real (tlons(si2)) )

         if (dist > max_coordinate_drift) then

            nsites_coord_mismatch = nsites_coord_mismatch + 1
            				! count each mismatched site in file

            max_mismatch_distance &		   ! find max distance
               = max (max_mismatch_distance, dist)   ! in entire run

            if (diag >= 3) then
               print *
               print *, '*** read_obs_series: Warning:'
               print *, '*** Difference in coordinates between input files' &
                  // ' files exceeds limit.'
               print *, '*** Site ID = ' // trim (tids(si2))
               print '(a,2f12.5)', ' *** Previous coordinates     =', &
                  tlats(si2), tlons(si2)
               print '(a,2f12.5)', ' *** Current file coordinates =', &
                  file_lats(si1), file_lons(si1)
               print '(a,f12.3,a)', ' *** Surface offset =', dist, ' Km'
               print '(a,f12.3,a)', ' *** Limit          =', &
                  max_coordinate_drift, ' Km'
               print *, '*** The newer coordinates will be used.'
            end if

! For mismatches, always replace older coordinates with the newer ones.

            tlats(si2) = file_lats(si1)
            tlons(si2) = file_lons(si1)
         end if

! Insert input data for current date into primary time series array.

         tdata(ti1:ti2,si2) = file_data(:,si1)

      end do site_loop

! Report file summary in case of mismatched coordinates.

      if (nsites_coord_mismatch /= 0) then
         nfiles_coord_mismatch = nfiles_coord_mismatch + 1
         				! count files with mismatched coords
         if (diag >= 1) then
            print '(2a,i5)',     '  *** Number of sites in this file with', &
               ' mismatched coordinates =', nsites_coord_mismatch
            print '(a,f12.2,a)', '  *** Maximum surface mismatch in file =', &
               max_mismatch_distance, ' Km'
            print *
         end if
      end if

      ndays_valid = ndays_valid + 1		! count valid input files
   end do date_loop

   if (diag >= 2) print *
   if (diag >= 2) print *, ' End of requested time range.'

! Print input summary, part 1.

   fmt1 = '(1x,a,i0)'

   print *,    '-------------------------------------------------------------'
   print *,    'Input summary, all BUFR files combined:'
   print fmt1, 'Total number of days in input period   = ', ndays
   print fmt1, 'Days skipped, missing input files      = ', ndays_missing
   print fmt1, 'Days skipped, invalid input files      = ', ndays_error
   print fmt1, 'Number of valid days read              = ', ndays_valid
   print *
   print fmt1, 'Number of files with mismatched coords = ',nfiles_coord_mismatch

! Controlled halt if all files missing.

   if (ndays_valid == 0) then
      print *
      print '(2a)', '*** read_obs_series: Fatal error, no valid input', &
         ' files.  Abort.'
      call exit (1)
   end if

!-----------------------------------------------------------
! Return all site data to caller.
!-----------------------------------------------------------

! Allocate output arrays for actual number of sites, all files combined.

   if (diag >= 4) print *, ' read_obs_series: Allocate output arrays.'

   allocate (site_ids(nsites), site_lats(nsites), site_lons(nsites))
   allocate (out_data(hour_dim,nsites))

! Copy all site data.

   if (diag >= 4) print *, ' Copy all site data to output arrays.'

   site_ids(:)   = tids(1:nsites)		! copy site ID's
   site_lats(:)  = tlats(1:nsites)		! copy coordinates
   site_lons(:)  = tlons(1:nsites)

   out_data(:,:) = tdata(:,1:nsites)		! copy data values (hours,sites)

! Count number of sites with all missing data.

   all_missing_count = 0

   do si = 1, nsites
      if (all (tdata(:,si) == vmiss)) all_missing_count = all_missing_count + 1
   end do

! Print input summary, part 2.

   print *
   print fmt1, 'Number of unique sites from all files = ', nsites
   print fmt1, 'Number of sites with all missing data = ', all_missing_count

   if (diag >= 2) print *
   if (diag >= 3) print *, 'read_obs_series: Return.'

end subroutine read_obs_series

end module read__obs_series
