help([[
This loads libraries for building the AQM-utils on
the NOAA operational machine WCOSS2 using Intel-19.1.3.304
]])

whatis([===[Loads libraries needed for building the AQM-utils on WCOSS2 ]===])

load(pathJoin("envvar", os.getenv("envvar_ver")))

load(pathJoin("PrgEnv-intel", os.getenv("PrgEnv_intel_ver")))
load(pathJoin("intel", os.getenv("intel_ver")))
load(pathJoin("craype", os.getenv("craype_ver")))
load(pathJoin("cray-mpich", os.getenv("cray_mpich_ver")))

load(pathJoin("cmake", os.getenv("cmake_ver")))

setenv("HPC_OPT","/apps/ops/para/libs")
prepend_path("MODULEPATH", pathJoin("/apps/ops/para/libs/modulefiles/compiler/intel", os.getenv("intel_ver")))
prepend_path("MODULEPATH", pathJoin("/apps/ops/para/libs/modulefiles/mpi/intel", os.getenv("intel_ver"), "cray-mpich", os.getenv("cray_mpich_ver")))

load(pathJoin("netcdf", os.getenv("netcdf_ver")))
load(pathJoin("bacio", os.getenv("bacio_ver")))
load(pathJoin("bufr", os.getenv("bufr_ver")))
load(pathJoin("g2", os.getenv("g2_ver")))
load(pathJoin("libpng", os.getenv("libpng_ver")))
load(pathJoin("w3nco", os.getenv("w3nco_ver")))
load(pathJoin("w3emc", os.getenv("w3emc_ver")))
load(pathJoin("nemsio", os.getenv("nemsio_ver")))
load(pathJoin("nemsiogfs", os.getenv("nemsiogfs_ver")))
load(pathJoin("sigio", os.getenv("sigio_ver")))
load(pathJoin("wgrib2", os.getenv("wgrib2_ver")))
load(pathJoin("zlib", os.getenv("zlib_ver")))
load(pathJoin("jasper", os.getenv("jasper_ver")))

load(pathJoin("cray-pals", os.getenv("cray_pals_ver")))

setenv("CMAKE_C_COMPILER","cc")
setenv("CMAKE_CXX_COMPILER","CC")
setenv("CMAKE_Fortran_COMPILER","ftn")
setenv("CMAKE_Platform","wcoss2")

