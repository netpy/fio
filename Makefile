# 条件判断：检查SRCDIR变量是否为空
# 如果为空，则将SRCDIR设置为当前目录(.)
ifeq ($(SRCDIR),)
SRCDIR := .
endif

# 设置源文件搜索路径
VPATH := $(SRCDIR)

# all: Makefile的默认目标，make命令默认执行的第一个规则
# fio：all目标的依赖项，表示构建all需要先构建fio
all: fio	

# 目标：config-host.mak - fio项目的核心配置文件
# 依赖：configure - 项目的配置脚本
# 命令：条件执行的shell脚本
# 检查config-host.mak是否存在，
# 情况1：配置文件不存在：则打印提示信息，并运行configure脚本生成配置文件
# 情况2：配置文件已存在但可能过时：打印提示信息，提取并重新执行配置命令
#  		使用sed从config-host.mak文件中提取之前使用的配置命令并重新执行，保留用户的配置选项。
# 是否过时是通过检查依赖目标的时间戳实现的，这里是configure脚本
# 如果configure脚本的修改时间比config-host.mak新 → config-host.mak过时
config-host.mak: configure
	@if [ ! -e "$@" ]; then					\
	  echo "Running configure ...";				\
	  ./configure;						\
	else							\
	  echo "$@ is out-of-date, running configure";		\
	  sed -n "/.*Configured with/s/[^:]*: //p" "$@" | sh;	\
	fi

# 条件包含语句，用于选择性地包含配置文件
# $(MAKECMDGOALS)：Make的内置变量，包含用户在命令行指定的目标（如fio、clean、test等）
# 如果用户执行的不是make clean命令，则包含config-host.mak配置文件
# 目的：
# 如果用户没有运行过configure，config-host.mak不存在，make clean会失败;
# 即使存在，包含配置文件对于clean操作也是不必要的开销
ifneq ($(MAKECMDGOALS),clean)
include config-host.mak
endif

# 核心编译器选项和目标定义，每个变量都有特定的作用和配置意图。
# 1. 调试相关选项
# 定义调试宏FIO_INC_DEBUG，用于启用fio内部的调试功能
DEBUGFLAGS = -DFIO_INC_DEBUG
# 2. 预处理器选项
# -D_LARGEFILE_SOURCE：启用大文件支持（POSIX标准），用于处理大于2GB的文件
# -D_FILE_OFFSET_BITS=64：指定文件偏移量的字节数为64位（默认32位）
# -DFIO_INTERNAL：定义内部宏，用于在fio内部使用
# $(DEBUGFLAGS)：包含调试宏，用于启用调试功能
# +=：追加到现有CPPFLAGS，保留用户可能已设置的值
CPPFLAGS+= -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -DFIO_INTERNAL $(DEBUGFLAGS)
# 3. 优化选项
# -g：生成调试信息，便于调试工具（如gdb）使用
# -ffast-math：启用快速数学运算，牺牲部分精度换取性能
OPTFLAGS= -g -ffast-math
# 4. C编译器核心选项
# -std=gnu99：使用GNU扩展的C99标准
# -Wwrite-strings：将字符串常量视为const char*，防止意外修改
# -Wall：启用几乎所有警告
# -Wdeclaration-after-statement：警告语句后的变量声明（C99前不允许）
# $(OPTFLAGS)：包含前面定义的优化选项
# $(EXTFLAGS)/$(BUILD_CFLAGS)：额外的外部和构建特定选项
# -I. -I$(SRCDIR)：头文件搜索路径（当前目录和源文件目录）
FIO_CFLAGS= -std=gnu99 -Wwrite-strings -Wall -Wdeclaration-after-statement $(OPTFLAGS) $(EXTFLAGS) $(BUILD_CFLAGS) -I. -I$(SRCDIR)
# 5. 链接选项
# -lm：链接数学库
# $(EXTLIBS)：外部依赖库，由configure脚本检测
LIBS	+= -lm $(EXTLIBS)
# 6. 目标定义:指定主程序目标，最终生成fio可执行文件
PROGS	= fio
# 定义需要安装的辅助脚本列表
# $(addprefix $(SRCDIR)/,...)：为所有脚本路径添加$(SRCDIR)/前缀
SCRIPTS = $(addprefix $(SRCDIR)/,tools/fio_generate_plots tools/plot/fio2gnuplot tools/genfio tools/fiologparser.py tools/hist/fiologparser_hist.py tools/hist/fio-histo-log-pctiles.py tools/fio_jsonplus_clat2csv)

# 关键配置解析
# 1. 优化级别控制
# ifndef CONFIG_FIO_NO_OPT：如果没有定义CONFIG_FIO_NO_OPT宏（即未禁用优化）
# -O3：启用最高级别优化（优化速度和大小，可能增加编译时间）
# 实际效果：从config-host.mak看，此配置会被启用，因为CONFIG_FIO_NO_OPT未定义
ifndef CONFIG_FIO_NO_OPT
  FIO_CFLAGS += -O3
endif
# 2. 本地架构优化
# ifdef CONFIG_BUILD_NATIVE：如果定义了CONFIG_BUILD_NATIVE宏
# -march=native：针对本地CPU架构进行指令集优化，生成特定于当前CPU的代码
# 实际效果：从config-host.mak看，CONFIG_BUILD_NATIVE=y，此优化会被启用
ifdef CONFIG_BUILD_NATIVE
  FIO_CFLAGS += -march=native
endif

# 3. Windows PDB调试信息（条件编译）
# ifdef CONFIG_PDB：如果定义了CONFIG_PDB宏（Windows平台PDB调试信息）
# -gcodeview：生成CodeView格式调试信息（Windows平台使用）
# -Wl,-pdb,...：生成PDB调试文件
# -fuse-ld=lld：使用LLVM链接器
# 实际效果：从config-host.mak看，CONFIG_PDB未定义，此配置不会被启用
ifdef CONFIG_PDB
  LINK_PDBFILE ?= -Wl,-pdb,$(dir $@)/$(basename $(@F)).pdb
  FIO_CFLAGS += -gcodeview
  LDFLAGS += -fuse-ld=lld $(LINK_PDBFILE)
endif

# If clang, do not use builtin stpcpy as it breaks the build
# 4. Clang编译器兼容性
# ifeq ($(CC),clang)：如果使用Clang编译器
# -fno-builtin-stpcpy：禁用Clang内置的stpcpy函数实现
# 设计意图：解决Clang内置stpcpy函数可能导致的编译错误
# 实际效果：从config-host.mak看，CC=gcc，此配置不会被启用
ifeq ($(CC),clang)
  FIO_CFLAGS += -fno-builtin-stpcpy
endif

# 5. GFIO图形界面支持
# ifdef CONFIG_GFIO：如果定义了CONFIG_GFIO宏（启用GFIO图形界面）
# PROGS += gfio：将gfio添加到需要构建的程序列表
# 实际效果：从config-host.mak看，CONFIG_GFIO未定义，不会构建GFIO
ifdef CONFIG_GFIO
  PROGS += gfio
endif

# 文件列表构建
# (1) CRC目录源文件
# $(wildcard $(SRCDIR)/crc/*.c)：查找所有在$(SRCDIR)/crc/目录下的.c源文件
# $(patsubst $(SRCDIR)/%,%,...)：将找到的文件名中的$(SRCDIR)/前缀移除，只保留相对路径
# $(sort ...)：对处理后的文件列表进行排序，确保顺序一致
# (2) lib目录源文件：与CRC目录类似，获取并处理$(SRCDIR)/lib/目录下的所有.c源文件
# (3) 直接列出的源文件
# 在项目中的作用
# 源文件统一管理：将所有核心源文件集中在一个变量中，便于后续统一处理
# 目标文件生成：后续会通过OBJS := $(SOURCE:.c=.o)将所有源文件转换为对应的目标文件（.o）
# 编译和链接：最终用于构建fio可执行文件和相关工具
SOURCE :=	$(sort $(patsubst $(SRCDIR)/%,%,$(wildcard $(SRCDIR)/crc/*.c)) \
		$(patsubst $(SRCDIR)/%,%,$(wildcard $(SRCDIR)/lib/*.c))) \
		gettime.c ioengines.c init.c stat.c log.c time.c filesetup.c \
		eta.c verify.c memory.c io_u.c parse.c fio_sem.c rwlock.c \
		pshared.c options.c fio_shared_sem.c \
		smalloc.c filehash.c profile.c debug.c engines/cpu.c \
		engines/mmap.c engines/sync.c engines/null.c engines/net.c \
		engines/ftruncate.c engines/fileoperations.c \
		engines/exec.c \
		server.c client.c iolog.c backend.c libfio.c flow.c cconv.c \
		gettime-thread.c helpers.c json.c idletime.c td_error.c \
		profiles/tiobench.c profiles/act.c io_u_queue.c filelock.c \
		workqueue.c rate-submit.c optgroup.c helper_thread.c \
		steadystate.c zone-dist.c zbd.c dedupe.c dataplacement.c \
		sprandom.c

# HDFS存储引擎配置 (CONFIG_LIBHDFS)
# 条件判断：当配置了CONFIG_LIBHDFS时启用HDFS引擎支持
# 编译选项：
# 	HDFSFLAGS：设置HDFS相关的头文件搜索路径，包括Java SDK和HDFS库的头文件
# 	FIO_CFLAGS += $(HDFSFLAGS)：将HDFS编译选项添加到全局编译标志中
# 链接选项：
# 	HDFSLIB：配置HDFS库的链接参数，包括：
# 	 -Wl,-rpath：设置运行时库搜索路径
# 	 -L：设置编译时库搜索路径
# 	 libhdfs.a：HDFS静态库
# 	 -ljvm：Java虚拟机库
# 源文件：将engines/libhdfs.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LIBHDFS
  HDFSFLAGS= -I $(JAVA_HOME)/include -I $(JAVA_HOME)/include/linux -I $(FIO_LIBHDFS_INCLUDE)
  HDFSLIB= -Wl,-rpath $(JAVA_HOME)/lib/$(FIO_HDFS_CPU)/server -L$(JAVA_HOME)/lib/$(FIO_HDFS_CPU)/server $(FIO_LIBHDFS_LIB)/libhdfs.a -ljvm
  FIO_CFLAGS += $(HDFSFLAGS)
  SOURCE += engines/libhdfs.c
endif

# iSCSI存储引擎配置 (CONFIG_LIBISCSI)
# 条件判断：当配置了CONFIG_LIBISCSI时启用iSCSI引擎支持
# 编译选项：
# 	libiscsi_SRCS：iSCSI引擎的源文件列表
# 	libiscsi_LIBS：iSCSI引擎的链接库列表
# 	libiscsi_CFLAGS：iSCSI引擎的编译选项
# 链接选项：
# 	libiscsi_LIBS：iSCSI引擎的链接库列表
# 源文件：将engines/libiscsi.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LIBISCSI
  libiscsi_SRCS = engines/libiscsi.c
  libiscsi_LIBS = $(LIBISCSI_LIBS)
  libiscsi_CFLAGS = $(LIBISCSI_CFLAGS)
  ENGINES += libiscsi
endif

# NBD存储引擎配置 (CONFIG_LIBNBD)
# 条件判断：当配置了CONFIG_LIBNBD时启用NBD引擎支持
# 编译选项：
# 	nbd_SRCS：NBD引擎的源文件列表
# 	nbd_LIBS：NBD引擎的链接库列表
# 	nbd_CFLAGS：NBD引擎的编译选项
# 链接选项：
# 	nbd_LIBS：NBD引擎的链接库列表
# 源文件：将engines/nbd.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LIBNBD
  nbd_SRCS = engines/nbd.c
  nbd_LIBS = $(LIBNBD_LIBS)
  nbd_CFLAGS = $(LIBNBD_CFLAGS)
  ENGINES += nbd
endif

# NFS存储引擎配置 (CONFIG_LIBNFS)
# 条件判断：当配置了CONFIG_LIBNFS时启用NFS引擎支持
# 编译选项：
# 	CFLAGS += $(LIBNFS_CFLAGS)：将NFS编译选项添加到全局编译标志中
# 链接选项：
# 	LIBS += $(LIBNFS_LIBS)：将NFS链接库添加到全局链接库列表中
# 源文件：将engines/nfs.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LIBNFS
  CFLAGS += $(LIBNFS_CFLAGS)
  LIBS += $(LIBNFS_LIBS)
  SOURCE += engines/nfs.c
endif

# 64位系统配置
# 条件判断：当配置了CONFIG_64BIT时启用64位系统支持
# 编译选项：
# 	CPPFLAGS += -DBITS_PER_LONG=64：将64位系统相关的编译选项添加到全局编译标志中
# 	CPPFLAGS += -DBITS_PER_LONG=32：将32位系统相关的编译选项添加到全局编译标志中
ifdef CONFIG_64BIT
  CPPFLAGS += -DBITS_PER_LONG=64
else ifdef CONFIG_32BIT
  CPPFLAGS += -DBITS_PER_LONG=32
endif
# AIO存储引擎配置 (CONFIG_LIBAIO)
# 条件判断：当配置了CONFIG_LIBAIO时启用AIO引擎支持
# 编译选项：
# 	libaio_SRCS：AIO引擎的源文件列表
# 	cmdprio_SRCS：AIO引擎的优先级源文件列表
# 	LIBS += -laio：将AIO库添加到全局链接库列表中
# 	libaio_LIBS = -laio：将AIO库添加到AIO引擎的链接库列表中
# 源文件：将engines/libaio.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LIBAIO
  libaio_SRCS = engines/libaio.c
  cmdprio_SRCS = engines/cmdprio.c
  LIBS += -laio
  libaio_LIBS = -laio
  ENGINES += libaio
endif
# RDMA存储引擎配置 (CONFIG_RDMA)
# 条件判断：当配置了CONFIG_RDMA时启用RDMA引擎支持
# 编译选项：
# 	rdma_SRCS：RDMA引擎的源文件列表
# 	rdma_LIBS：RDMA引擎的链接库列表
# 源文件：将engines/rdma.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_RDMA
  rdma_SRCS = engines/rdma.c
  rdma_LIBS = -libverbs -lrdmacm
  ENGINES += rdma
endif
# POSIX AIO存储引擎配置 (CONFIG_POSIXAIO)
# 条件判断：当配置了CONFIG_POSIXAIO时启用POSIX AIO引擎支持
# 编译选项：
# 	SOURCE += engines/posixaio.c：将POSIX AIO引擎的源文件添加到全局源文件列表SOURCE中
# 源文件：将engines/posixaio.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_POSIXAIO
  SOURCE += engines/posixaio.c
endif
# Linux Fallocate存储引擎配置 (CONFIG_LINUX_FALLOCATE)
# 条件判断：当配置了CONFIG_LINUX_FALLOCATE时启用Linux Fallocate引擎支持
# 编译选项：
# 	SOURCE += engines/falloc.c：将Linux Fallocate引擎的源文件添加到全局源文件列表SOURCE中
# 源文件：将engines/falloc.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LINUX_FALLOCATE
  SOURCE += engines/falloc.c
endif
# Linux EXT4 Move Extent存储引擎配置 (CONFIG_LINUX_EXT4_MOVE_EXTENT)
# 条件判断：当配置了CONFIG_LINUX_EXT4_MOVE_EXTENT时启用Linux EXT4 Move Extent引擎支持
# 编译选项：
# 	SOURCE += engines/e4defrag：将Linux EXT4 Move Extent引擎的源文件添加到全局源文件列表SOURCE中
# 源文件：将engines/e4defrag.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LINUX_EXT4_MOVE_EXTENT
  SOURCE += engines/e4defrag.c
endif
# libcufile存储引擎配置 (CONFIG_LIBCUFILE)
# 条件判断：当配置了CONFIG_LIBCUFILE时启用libcufio引擎支持
# 编译选项：
# 	SOURCE += engines/libcufile.c：将libcufio引擎的源文件添加到全局源文件列表SOURCE中
# 源文件：将engines/libcufile.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LIBCUFILE
  SOURCE += engines/libcufile.c
endif
# Linux Splice存储引擎配置 (CONFIG_LINUX_SPLICE)
# 条件判断：当配置了CONFIG_LINUX_SPLICE时启用Linux Splice引擎支持
# 编译选项：
# 	SOURCE += engines/splice.c：将Linux Splice引擎的源文件添加到全局源文件列表SOURCE中
# 源文件：将engines/splice.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_LINUX_SPLICE
  SOURCE += engines/splice.c
endif
# Solaris AIO存储引擎配置 (CONFIG_SOLARISAIO)
# 条件判断：当配置了CONFIG_SOLARISAIO时启用Solaris AIO引擎支持
# 编译选项：
# 	SOURCE += engines/solarisaio.c：将Solaris AIO引擎的源文件添加到全局源文件列表SOURCE中
# 源文件：将engines/solarisaio.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_SOLARISAIO
  SOURCE += engines/solarisaio.c
endif
# Windows AIO存储引擎配置 (CONFIG_WINDOWSAIO)
# 条件判断：当配置了CONFIG_WINDOWSAIO时启用Windows AIO引擎支持
# 编译选项：
# 	SOURCE += engines/windowsaio.c：将Windows AIO引擎的源文件添加到全局源文件列表SOURCE中
# 源文件：将engines/windowsaio.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_WINDOWSAIO
  SOURCE += engines/windowsaio.c
endif
# Rados存储引擎配置 (CONFIG_RADOS)
# 条件判断：当配置了CONFIG_RADOS时启用Rados引擎支持
# 编译选项：
# 	rados_SRCS：Rados引擎的源文件列表
# 	rados_LIBS：Rados引擎的链接库列表
# 源文件：将engines/rados.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_RADOS
  rados_SRCS = engines/rados.c
  rados_LIBS = -lrados
  ENGINES += rados
endif
# RBD存储引擎配置 (CONFIG_RBD)
# 条件判断：当配置了CONFIG_RBD时启用RBD引擎支持
# 编译选项：
# 	rbd_SRCS：RBD引擎的源文件列表
# 	rbd_LIBS：RBD引擎的链接库列表
# 源文件：将engines/rbd.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_RBD
  rbd_SRCS = engines/rbd.c
  rbd_LIBS = -lrbd -lrados
  ENGINES += rbd
endif
# HTTP存储引擎配置 (CONFIG_HTTP)
# 条件判断：当配置了CONFIG_HTTP时启用HTTP引擎支持
# 编译选项：
# 	http_SRCS：HTTP引擎的源文件列表
# 	http_LIBS：HTTP引擎的链接库列表
# 源文件：将engines/http.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_HTTP
  http_SRCS = engines/http.c
  http_LIBS = -lcurl -lssl -lcrypto
  ENGINES += http
endif
# DFS存储引擎配置 (CONFIG_DFS)
# 条件判断：当配置了CONFIG_DFS时启用DFS引擎支持
# 编译选项：
# 	dfs_SRCS：DFS引擎的源文件列表
# 	dfs_LIBS：DFS引擎的链接库列表
# 源文件：将engines/dfs.c直接添加到全局源文件列表SOURCE中
ifdef CONFIG_DFS
  dfs_SRCS = engines/dfs.c
  dfs_LIBS = -luuid -ldaos -ldfs
  ENGINES += dfs
endif

# 始终包含的兼容性文件
# 无条件包含asprintf.c，这是一个用于动态分配字符串的函数实现，确保在所有平台上都有一致的行为。
SOURCE += oslib/asprintf.c
# 条件包含的兼容性文件 对于多个标准库或系统调用函数，采用ifndef CONFIG_XXX条件判断：
# CONFIG_STRSEP：字符串分割函数
# CONFIG_STRCASESTR：大小写不敏感的字符串查找
# CONFIG_STRLCAT：字符串安全拼接
# CONFIG_HAVE_STRNDUP：安全的字符串复制（带长度限制）
# CONFIG_GETOPT_LONG_ONLY：长选项命令行解析
# CONFIG_INET_ATON：IPv4地址字符串转换
# CONFIG_HAVE_STATX：扩展文件状态查询
ifndef CONFIG_STRSEP
  SOURCE += oslib/strsep.c
endif
ifndef CONFIG_STRCASESTR
  SOURCE += oslib/strcasestr.c
endif
ifndef CONFIG_STRLCAT
  SOURCE += oslib/strlcat.c
endif
ifndef CONFIG_HAVE_STRNDUP
  SOURCE += oslib/strndup.c
endif
ifndef CONFIG_GETOPT_LONG_ONLY
  SOURCE += oslib/getopt_long.c
endif
ifndef CONFIG_INET_ATON
  SOURCE += oslib/inet_aton.c
endif
ifndef CONFIG_HAVE_STATX
  SOURCE += oslib/statx.c
endif
# 作用：仅当定义了CONFIG_GFAPI宏时，才编译和链接GlusterFS相关代码
# 	glusterfs.c：GlusterFS引擎的核心实现，包含通用功能（如连接管理、选项解析）
# 	glusterfs_sync.c：同步I/O操作的实现
# 	glusterfs_async.c：异步I/O操作的实现
# 作用：将这些源文件添加到全局源文件列表SOURCE中，参与最终编译
# 链接库配置:
# 	-lgfapi：链接GlusterFS API库（GlusterFS File API）
# 	-lglusterfs：链接GlusterFS库（GlusterFS File System）
# 高级功能选项
# CONFIG_GF_FADVISE：表示是否启用GlusterFS的fadvise功能
# -DGFAPI_USE_FADVISE：在编译时定义该宏，启用引擎中的fadvise相关代码
# 作用：提供更精细的I/O调度控制，优化性能
ifdef CONFIG_GFAPI
  SOURCE += engines/glusterfs.c
  SOURCE += engines/glusterfs_sync.c
  SOURCE += engines/glusterfs_async.c
  LIBS += -lgfapi -lglusterfs
  ifdef CONFIG_GF_FADVISE
    FIO_CFLAGS += "-DGFAPI_USE_FADVISE"
  endif
endif
# MTD引擎配置
# 功能：为MTD（Memory Technology Device）设备提供I/O支持
# 实现：
# engines/mtd.c：MTD引擎核心实现，支持读写MTD字符设备
# oslib/libmtd.c：MTD设备操作库，提供擦除块管理等功能
# oslib/libmtd_legacy.c：旧内核版本的MTD支持，通过/proc/mtd接口获取设备信息
# 关键特性：支持坏块检测与标记、按擦除块大小分割I/O操作
ifdef CONFIG_MTD
  SOURCE += engines/mtd.c
  SOURCE += oslib/libmtd.c
  SOURCE += oslib/libmtd_legacy.c
endif
# Device DAX引擎配置
# 功能：直接访问DAX（Direct Access）设备的I/O引擎
# 实现：
# 	engines/dev-dax.c：使用mmap直接映射DAX设备进行内存访问
# 依赖：链接pmem库（-lpmem）
# 关键特性：
# 	无需O_DIRECT标志，直接内存访问
# 	要求块大小符合设备DAX对齐要求
# 	支持最多1GiB的映射文件（模仿mmap引擎行为）
ifdef CONFIG_LINUX_DEVDAX
  dev-dax_SRCS = engines/dev-dax.c
  dev-dax_LIBS = -lpmem
  ENGINES += dev-dax
endif
# libpmem引擎配置
# 功能：使用PMDK libpmem库的I/O引擎
# 实现：
# 	engines/libpmem.c：利用libpmem的pmem_memcpy等函数进行持久化内存访问
# 依赖：链接pmem库（-lpmem）
# 关键特性：
# 	要求PMDK版本>=1.5
# 	支持sync=1选项（每次写操作执行pmem_drain()）
# 	支持direct=1选项（设置PMEM_F_MEM_NONTEMPORAL标志）
# 	要求DAX-capable文件系统并启用DAX挂载
ifdef CONFIG_LIBPMEM
  libpmem_SRCS = engines/libpmem.c
  libpmem_LIBS = -lpmem
  ENGINES += libpmem
endif
# IME引擎配置
# 功能：DDN's Infinite Memory Engine的I/O引擎
# 实现：
# 	engines/ime.c：实现了三种IME引擎变体（ime_psync、ime_psyncv、ime_aio）
# 关键特性：
# 	支持同步和异步I/O
# 	支持IO向量批量处理
# 	使用ime_native库进行高性能内存访问
ifdef CONFIG_IME
  SOURCE += engines/ime.c
endif
# ZBC/SMR硬盘支持 (libzbc引擎)
# 核心功能：为Zoned Block Devices (ZBD)和Shingled Magnetic Recording (SMR)硬盘提供I/O支持
# 实现文件：engines/libzbc.c
# 	基于libzbc库提供的ZBC API
# 	支持ZBC设备的特定特性如顺序写入区域和随机写入区域
# 	提供设备信息获取、扇区计算等功能
# 依赖库：-lzbc - 链接libzbc库
ifdef CONFIG_LIBZBC
  libzbc_SRCS = engines/libzbc.c
  libzbc_LIBS = -lzbc
  ENGINES += libzbc
endif
# NVMe设备支持 (xnvme引擎)
# 核心功能：通过xNVMe API提供对NVMe设备的高效访问
# 实现文件：engines/xnvme.c
# 	支持NVMe控制器和设备的管理
# 	提供同步和异步I/O操作
# 	支持NVMe保护信息(NVMe PI)
# 	支持元数据(metadata)处理
# 依赖库：$(LIBXNVME_LIBS) - 动态获取libxnvme相关库
# 编译选项：$(LIBXNVME_CFLAGS) - 动态获取libxnvme相关编译标志
# 高级特性：
# 	支持高优先级队列
# 	支持轮询模式
# 	可配置的设备命名空间(NSID)
# 	可自定义后端、内存分配器和异步操作方式
ifdef CONFIG_LIBXNVME
  xnvme_SRCS = engines/xnvme.c
  xnvme_LIBS = $(LIBXNVME_LIBS)
  xnvme_CFLAGS = $(LIBXNVME_CFLAGS)
  ENGINES += xnvme
endif
# 通用块I/O支持 (libblkio引擎)
# 核心功能：通过libblkio库提供对多种块I/O接口的统一访问
# 实现文件：engines/libblkio.c
# 	支持多种驱动后端
# 	提供向量I/O支持
#	支持多种完成等待模式(阻塞、事件fd、循环轮询)
# 配置与依赖
# 	依赖库：$(LIBBLKIO_LIBS) - 动态获取libblkio相关库
# 	编译选项：$(LIBBLKIO_CFLAGS) - 动态获取libblkio相关编译标志
# 	关键特性：
# 		可配置的驱动名称和路径
# 		支持连接前和启动前属性设置
# 		支持高优先级队列
# 		支持向量I/O操作
# 		支持写零操作代替TRIM
ifdef CONFIG_LIBBLKIO
  libblkio_SRCS = engines/libblkio.c
  libblkio_LIBS = $(LIBBLKIO_LIBS)
  libblkio_CFLAGS = $(LIBBLKIO_CFLAGS)
  ENGINES += libblkio
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), Linux) 检查确保以下设置仅在为 Linux 编译时应用。
# 源文件：当为 Linux 编译时，会添加以下源文件：
# 	diskutil.c - 磁盘实用功能
# 	fifo.c - FIFO（先进先出）缓冲区实现
# 	blktrace.c - 块设备跟踪功能
# 	cgroup.c - 控制组（cgroup）集成
# 	trim.c - SSD 的 TRIM 命令支持
# 	engines/sg.c - SCSI 通用 I/O 引擎
# 	oslib/linux-dev-lookup.c - Linux 设备查找工具
# 	engines/io_uring.c - io_uring I/O 引擎（现代 Linux I/O 接口）
# 	engines/nvme.c - NVMe 存储设备支持
# 命令优先级源：设置 cmdprio_SRCS 为 engines/cmdprio.c，可能实现命令优先级功能。
# 块分区设备支持：如果定义了 CONFIG_HAS_BLKZONED，则添加 oslib/linux-blkzoned.c 用于块分区设备支持。
# 库和链接器标志：
# 向 LIBS 添加 -lpthread（POSIX 线程库）和 -ldl（动态链接库）
# 向 LDFLAGS 添加 -rdynamic，告诉链接器将所有符号添加到动态符号表，这对调试和需要引用可执行文件符号的库很有用
ifeq ($(CONFIG_TARGET_OS), Linux)
  SOURCE += diskutil.c fifo.c blktrace.c cgroup.c trim.c engines/sg.c \
		oslib/linux-dev-lookup.c engines/io_uring.c engines/nvme.c
  cmdprio_SRCS = engines/cmdprio.c
ifdef CONFIG_HAS_BLKZONED
  SOURCE += oslib/linux-blkzoned.c
endif
  LIBS += -lpthread -ldl
  LDFLAGS += -rdynamic
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), Android) 检查确保以下设置仅在为 Android 编译时应用。
# 源文件：当为 Android 编译时，会添加以下源文件：
# 命令优先级源：设置 cmdprio_SRCS 为 engines/cmdprio.c，与 Linux 版本相同。
# 块分区设备支持：如果定义了 CONFIG_HAS_BLKZONED，则添加 oslib/linux-blkzoned.c 用于块分区设备支持，与 Linux 版本相同。
# 与 Linux 版本的主要区别：
# Android 版本包含了 profiles/tiobench.c 文件，这可能是为了在 Android 平台上提供 TIO 基准测试功能
# Android 版本使用 -llog 库而不是 -lpthread，因为 Android 系统的日志系统与标准 Linux 不同
# 库的顺序不同：Android 版本是 -ldl -llog，而 Linux 版本是 -lpthread -ldl
ifeq ($(CONFIG_TARGET_OS), Android)
  SOURCE += diskutil.c fifo.c blktrace.c cgroup.c trim.c profiles/tiobench.c \
		oslib/linux-dev-lookup.c engines/io_uring.c engines/nvme.c \
		engines/sg.c
  cmdprio_SRCS = engines/cmdprio.c
ifdef CONFIG_HAS_BLKZONED
  SOURCE += oslib/linux-blkzoned.c
endif
  LIBS += -ldl -llog
  LDFLAGS += -rdynamic
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), SunOS) 检查确保以下设置仅在为 SunOS 编译时应用。
# 库和编译标志：
# 	向 LIBS 添加 -lpthread（POSIX 线程库）和 -ldl（动态链接库）
# 	向 CPPFLAGS 添加 -D__EXTENSIONS__ 定义，这是 SunOS 特有的编译标志，用于启用某些扩展功能
ifeq ($(CONFIG_TARGET_OS), FreeBSD)
  SOURCE += trim.c
  LIBS	 += -lpthread -lrt
  LDFLAGS += -rdynamic
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), OpenBSD) 检查确保以下设置仅在为 OpenBSD 编译时应用。
# 库和链接器标志：
# 	向 LIBS 添加 -lpthread（POSIX 线程库）
# 	向 LDFLAGS 添加 -rdynamic，与 Linux 版本相同
ifeq ($(CONFIG_TARGET_OS), OpenBSD)
  LIBS	 += -lpthread
  LDFLAGS += -rdynamic
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), NetBSD) 检查确保以下设置仅在为 NetBSD 编译时应用。
# 库和链接器标志：
# 向 LIBS 添加 -lpthread（POSIX 线程库）和 -lrt（实时库，提供实时时钟和计时器功能）
# 向 LDFLAGS 添加 -rdynamic，与 Linux 和 OpenBSD 版本相同
ifeq ($(CONFIG_TARGET_OS), NetBSD)
  LIBS	 += -lpthread -lrt
  LDFLAGS += -rdynamic
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), DragonFly) 检查确保以下设置仅在为 DragonFly BSD 编译时应用。
# 源文件：当为 DragonFly BSD 编译时，会添加 trim.c 文件，该文件提供 SSD 的 TRIM 命令支持。
# 库和链接器标志：
# 	向 LIBS 添加 -lpthread（POSIX 线程库）和 -lrt（实时库，提供实时时钟和计时器功能）
# 	向 LDFLAGS 添加 -rdynamic，与 Linux、OpenBSD 和 NetBSD 版本相同
ifeq ($(CONFIG_TARGET_OS), DragonFly)
  SOURCE += trim.c
  LIBS	 += -lpthread -lrt
  LDFLAGS += -rdynamic
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), AIX) 检查确保以下设置仅在为 AIX 编译时应用。
# 库和编译标志：
# 	向 LIBS 添加 -lpthread（POSIX 线程库）、-ldl（动态链接库）和 -lrt（实时库）
# 	向 CPPFLAGS 添加 -D_LARGE_FILES（启用大文件支持）和 -D__ppc__（定义 PowerPC 架构，AIX 主要运行在此架构上）
# 	向 LDFLAGS 添加：
# 		-L/opt/freeware/lib（指定库搜索路径，/opt/freeware 是 AIX 上常见的第三方软件安装目录）
# 		-Wl,-blibpath:/opt/freeware/lib:/usr/lib:/lib（指定运行时库搜索路径）
# 		-Wl,-bmaxdata:0x80000000（设置最大数据段大小为 2GB，这是 AIX 特有的链接器选项）
ifeq ($(CONFIG_TARGET_OS), AIX)
  LIBS	 += -lpthread -ldl -lrt
  CPPFLAGS += -D_LARGE_FILES -D__ppc__
  LDFLAGS += -L/opt/freeware/lib -Wl,-blibpath:/opt/freeware/lib:/usr/lib:/lib -Wl,-bmaxdata:0x80000000
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), HP-UX) 检查确保以下设置仅在为 HP-UX 编译时应用。
# 库和编译标志：
# 	向 LIBS 添加 -lpthread（POSIX 线程库）、-ldl（动态链接库）和 -lrt（实时库）
# 	向 FIO_CFLAGS 添加：
# 		-D_LARGEFILE64_SOURCE（启用 64 位大文件支持，允许处理大于 2GB 的文件）
# 		-D_XOPEN_SOURCE_EXTENDED（启用扩展的 X/Open 接口，提供额外的系统功能）
ifeq ($(CONFIG_TARGET_OS), HP-UX)
  LIBS   += -lpthread -ldl -lrt
  FIO_CFLAGS += -D_LARGEFILE64_SOURCE -D_XOPEN_SOURCE_EXTENDED
endif
# 条件编译：ifeq ($(CONFIG_TARGET_OS), Darwin) 检查确保以下设置仅在为 Darwin（macOS）编译时应用。
# 库：向 LIBS 添加 -lpthread（POSIX 线程库）和 -ldl（动态链接库）。
# 源文件：添加 os/mac/posix.c 文件，这是 macOS 特有的 POSIX 接口实现，用于适配 macOS 平台的系统调用和功能。
ifeq ($(CONFIG_TARGET_OS), Darwin)
  LIBS	 += -lpthread -ldl
  SOURCE += os/mac/posix.c
endif
# 条件编译：ifneq (,$(findstring CYGWIN,$(CONFIG_TARGET_OS))) 检查确保以下设置仅在为 CYGWIN 编译时应用。
# 源文件：添加了以下 Windows 相关的源文件：
# 	os/windows/cpu-affinity.c - 处理 CPU 亲和性
# 	os/windows/posix.c - POSIX 接口实现，用于在 Windows 上模拟 POSIX 功能
# 	os/windows/dlls.c - 动态链接库相关功能
# 对象文件：设置 WINDOWS_OBJS 变量，包含上述源文件对应的对象文件以及 lib/hweight.o（可能是哈希权重计算相关）。
# 库：向 LIBS 添加多个 Windows 特定的库：
# 	-lpthread - POSIX 线程库
# 	-lpsapi - 进程状态 API 库，用于获取进程信息
# 	-lws2_32 - Windows 套接字 2.0 库，用于网络功能
# 	-lssp - 栈保护库，用于防止栈溢出攻击
# 编译标志：向 FIO_CFLAGS 添加：
# 	-DPSAPI_VERSION=1 - 定义 PSAPI 版本为 1
# 	-I$(SRCDIR)/os/windows/posix/include - 添加 POSIX 头文件搜索路径
# 	-Wno-format - 禁用格式警告
ifneq (,$(findstring CYGWIN,$(CONFIG_TARGET_OS)))
  SOURCE += os/windows/cpu-affinity.c os/windows/posix.c os/windows/dlls.c
  WINDOWS_OBJS = os/windows/cpu-affinity.o os/windows/posix.o os/windows/dlls.o lib/hweight.o
  LIBS	 += -lpthread -lpsapi -lws2_32 -lssp
  FIO_CFLAGS += -DPSAPI_VERSION=1 -I$(SRCDIR)/os/windows/posix/include -Wno-format
endif

# 条件编译：ifdef cmdprio_SRCS 检查 cmdprio_SRCS 变量是否已经被定义。
# 源文件添加：如果 cmdprio_SRCS 已定义，则将其包含的源文件添加到 SOURCE 变量中，这样在编译时就会包含这些文件。
# 上下文：在之前的代码片段中，我们可以看到在不同平台的配置中，cmdprio_SRCS 被设置为 engines/cmdprio.c
# cmdprio.c 文件可能实现了 I/O 命令优先级的功能，允许 fio 在测试过程中为不同的 I/O 操作设置优先级，这对于模拟真实应用场景中的 I/O 行为非常重要。
ifdef cmdprio_SRCS
  SOURCE += $(cmdprio_SRCS)
endif

# 处理动态引擎（dynamic engines）编译配置的部分。
# 条件编译：ifdef CONFIG_DYNAMIC_ENGINES 检查是否启用了动态引擎功能。
# 如果启用了动态引擎：
# 	将 ENGINES 变量的值赋给 DYNAMIC_ENGS
# 	定义一个名为 engine_template 的模板，用于为每个引擎生成编译规则：
# 		为每个引擎创建对应的目标文件列表（将源文件 .c 扩展名替换为 .o）
# 		为这些目标文件设置特定的编译标志：-fPIC（位置无关代码，用于生成共享库）
# 		为每个引擎生成一个共享库文件（.so），使用 -shared 标志进行链接
# 		设置共享库的 soname 为 fio-$(1).so.1
# 		将生成的共享库文件添加到 ENGS_OBJS 变量中
# 如果未启用动态引擎：
# 	定义一个不同的 engine_template 模板：
# 		将每个引擎的源文件直接添加到 SOURCE 变量中
# 		将每个引擎的库文件添加到 LIBS 变量中
# 		将每个引擎的编译标志添加到全局 CFLAGS 变量中
ifdef CONFIG_DYNAMIC_ENGINES
 DYNAMIC_ENGS := $(ENGINES)
define engine_template =
$(1)_OBJS := $$($(1)_SRCS:.c=.o)
$$($(1)_OBJS): CFLAGS := -fPIC $$($(1)_CFLAGS) $(CFLAGS)
engines/fio-$(1).so: $$($(1)_OBJS)
	$$(QUIET_LINK)$(CC) $(LDFLAGS) -shared -rdynamic -fPIC -Wl,-soname,fio-$(1).so.1 -o $$@ $$< $$($(1)_LIBS)
ENGS_OBJS += engines/fio-$(1).so
endef
else # !CONFIG_DYNAMIC_ENGINES
define engine_template =
SOURCE += $$($(1)_SRCS)
LIBS += $$($(1)_LIBS)
override CFLAGS += $$($(1)_CFLAGS)
endef
endif

# 目标规则定义：
# 	FIO-VERSION-FILE: FORCE：定义了一个目标 FIO-VERSION-FILE，依赖于 FORCE 目标
# 	FORCE 是一个特殊的依赖，通常在 Makefile 中定义为无命令的目标，确保每次构建时都会重新执行此规则
# 版本文件生成命令：
# 	@$(SHELL) $(SRCDIR)/FIO-VERSION-GEN：
# 		@ 前缀表示执行命令时不显示命令本身（静默执行）
# 		$(SHELL) 是当前使用的 shell 程序
# 		$(SRCDIR)/FIO-VERSION-GEN 是生成版本文件的脚本路径
# 		此脚本通常会基于 Git 提交历史、当前时间或其他信息生成版本号
# 包含版本文件：
# -include FIO-VERSION-FILE：
# 	- 前缀表示如果文件不存在也不会报错（静默包含）
# 	包含生成的版本文件，使其中定义的版本变量（如 FIO_VERSION 等）在 Makefile 中可用
FIO-VERSION-FILE: FORCE
	@$(SHELL) $(SRCDIR)/FIO-VERSION-GEN
-include FIO-VERSION-FILE

# 将版本信息嵌入到编译的程序中。
# override 是 Makefile 关键字，用于强制覆盖之前定义的 CFLAGS 变量，确保即使在命令行中传递了 CFLAGS，也会使用这里定义的值
# CFLAGS 是 C 编译器的编译标志变量
# -D 是 GCC 等编译器的标志，用于定义一个预处理宏
# FIO_VERSION 是宏的名称
# '"$(FIO_VERSION)"' 是宏的值，包含两层引号：
# 	内层双引号确保宏值是一个字符串
# 	外层单引号确保整个表达式作为一个参数传递给编译器
override CFLAGS := -DFIO_VERSION='"$(FIO_VERSION)"' $(FIO_CFLAGS) $(CFLAGS)

# $(foreach eng,$(ENGINES),...)：
# foreach 是 Makefile 的循环函数，语法为 $(foreach var,list,text)
# 遍历 $(ENGINES) 列表中的每个元素，将当前元素赋值给变量 eng
# 对每个 eng 执行后面的 text 部分
# call engine_template,$(eng)：调用之前定义的 engine_template 模板，传入参数 $(eng)（当前引擎名称）
# eval：将 call 函数返回的结果作为 Makefile 代码执行，生成实际的编译规则
$(foreach eng,$(ENGINES),$(eval $(call engine_template,$(eng))))

# 定义对象文件（object files）的部分，用于构建 fio 的不同可执行文件。
# 语法：使用 Makefile 的变量替换功能，将 SOURCE 变量中所有 .c 后缀的文件替换为 .o 后缀
# SOURCE 变量包含了 fio 的核心源文件，这行代码将它们转换为编译后的对象文件
OBJS := $(SOURCE:.c=.o)

# 作用：定义构建命令行工具 fio 所需的对象文件
# 组成：
# $(OBJS)：所有核心对象文件
# fio.o：主程序的对象文件（包含 main 函数）
FIO_OBJS = $(OBJS) fio.o

# 作用：定义构建图形界面工具 gfio 所需的对象文件
# 组成：
# $(OBJS)：所有核心对象文件（与 fio 共享）
# gfio.o：图形界面主程序的对象文件
# 其他多个与图形界面相关的对象文件：
GFIO_OBJS = $(OBJS) gfio.o graph.o tickmarks.o ghelpers.o goptions.o gerror.o \
			gclient.o gcompat.o cairo_text_helpers.o printing.o

# ifdef CONFIG_ARITHMETIC：检查是否定义了 CONFIG_ARITHMETIC 变量
# CONFIG_ARITHMETIC：这是一个配置选项，启用时会添加对算术表达式解析的支持
# lex.yy.o 和 y.tab.o：
# lex.yy.o：由 lex 生成的词法分析器对象文件
# y.tab.o：由 yacc/bison 生成的语法分析器对象文件
# 当启用 CONFIG_ARITHMETIC 时，fio 会添加对算术表达式的解析支持
# 这允许用户在 fio 配置文件中使用算术表达式，例如 size=10*1024k 或 runtime=60*60
# 词法分析器 (lex.yy.o) 负责将输入字符串分解为词法单元
# 语法分析器 (y.tab.o) 负责解析词法单元序列，构建语法树，并计算表达式值
ifdef CONFIG_ARITHMETIC
FIO_OBJS += lex.yy.o y.tab.o
GFIO_OBJS += lex.yy.o y.tab.o
endif

# -include：
# Makefile 的包含指令，- 前缀表示如果文件不存在也不会报错（静默忽略）
# 用于包含依赖文件（.d 文件），这些文件记录了源文件的依赖关系
# $(OBJS:.o=.d)：Makefile 变量替换语法，将 OBJS 变量中所有 .o 后缀的文件替换为 .d 后缀
# $(T_OBJS:.o=.d) 和 $(UT_OBJS:.o=.d)：类似地，将测试对象文件（T_OBJS）和单元测试对象文件（UT_OBJS）转换为对应的依赖文件
# .d 文件：由编译器在编译时自动生成（通常通过 -MMD 或 -MD 编译选项）
# 自动依赖管理：
# 例如：
# 	file.o: file.c header1.h header2.h
# 当 header1.h 或 header2.h 变化时，Make 会通过 .d 文件知道需要重新编译 file.c
# 避免了手动维护依赖关系的繁琐和可能的错误
-include $(OBJS:.o=.d) $(T_OBJS:.o=.d) $(UT_OBJS:.o=.d)

# ============================================================================
# smalloc内存分配器测试程序配置
# smalloc是fio项目中实现的一个简单内存分配器，用于进程间共享内存管理
# ============================================================================
# T_SMALLOC_OBJS：定义构建smalloc测试程序所需的所有目标文件
# t/stest.o：测试程序的主入口源文件，包含测试用例
# 添加smalloc测试所需的依赖模块：
# gettime.o：时间获取功能，用于性能测试和计时
# fio_sem.o：信号量实现，用于多线程环境下的同步
# pshared.o：进程间共享资源支持，smalloc的核心需求
# smalloc.o：smalloc内存分配器的核心实现
# t/log.o：测试框架的日志功能
# t/debug.o：测试框架的调试支持
# t/arch.o：架构相关的功能支持
# T_SMALLOC_PROGS：定义生成的smalloc测试程序的名称和路径
# 构建后将在t/目录下生成stest可执行文件
T_SMALLOC_OBJS = t/stest.o
T_SMALLOC_OBJS += gettime.o fio_sem.o pshared.o smalloc.o t/log.o t/debug.o \
		  t/arch.o
T_SMALLOC_PROGS = t/stest

# ============================================================================
# IEEE 754浮点数转换测试程序配置
# 用于测试fio项目中实现的IEEE 754浮点数与无符号整数之间的转换功能
# ============================================================================
# T_IEEE_OBJS：定义构建IEEE 754浮点数转换测试程序所需的所有目标文件
# t/ieee754.o：测试程序的主入口源文件，包含测试用例和验证逻辑
# 添加IEEE 754浮点数转换的核心实现
# lib/ieee754.o：包含pack754()和unpack754()函数，实现浮点数与整数的转换
# T_IEEE_PROGS：定义生成的IEEE 754测试程序的名称和路径
# 构建后将在t/目录下生成ieee754可执行文件
T_IEEE_OBJS = t/ieee754.o
T_IEEE_OBJS += lib/ieee754.o
T_IEEE_PROGS = t/ieee754

# ============================================================================
# ZIPF分布生成工具配置:
# 用于生成和分析zipf/pareto分布，帮助理解不同访问模式的特征
# 生成ZIPF分布：按照ZIPF定律生成访问模式数据
# 生成PARETO分布：支持Pareto分布的生成与分析
# 生成正态分布：支持正态(Normal)分布的生成
# 数据分析与可视化：将生成的数据分组并输出分析结果
# ============================================================================
# T_ZIPF_OBJS：定义构建ZIPF分布生成工具所需的目标文件列表
# t/genzipf.o：ZIPF分布生成工具的主源文件
# 添加ZIPF工具所需的依赖模块：
# t/log.o：日志功能模块
# lib/ieee754.o：IEEE 754浮点数转换功能
# lib/rand.o：随机数生成功能
# lib/pattern.o：模式生成功能
# lib/zipf.o：ZIPF分布算法核心实现
# lib/strntol.o：字符串转数字功能
# lib/gauss.o：高斯分布生成功能
# oslib/strcasestr.o：大小写不敏感字符串查找
# oslib/strndup.o：安全字符串复制功能
# T_ZIPF_PROGS：定义生成的ZIPF分布工具程序的名称和路径
# 构建后将在t/目录下生成fio-genzipf可执行文件
T_ZIPF_OBS = t/genzipf.o
T_ZIPF_OBJS += t/log.o lib/ieee754.o lib/rand.o lib/pattern.o lib/zipf.o \
		lib/strntol.o lib/gauss.o t/genzipf.o oslib/strcasestr.o \
		oslib/strndup.o
T_ZIPF_PROGS = t/fio-genzipf

# 用于构建 axmap 位图数据结构测试程序 的配置
# axmap是fio项目中实现的一种高效位图数据结构，采用多层位图设计
# 用于高效地跟踪和查找空闲块，适用于存储系统等需要大量位图操作的场景
# T_AXMAP_OBJS：定义构建axmap测试程序所需的目标文件列表
# t/axmap.o：axmap测试程序的主源文件，包含各种测试用例
# 添加axmap测试所需的依赖模块：
# lib/lfsr.o：线性反馈移位寄存器实现，用于生成伪随机位位置
# lib/axmap.o：axmap位图数据结构的核心实现
# T_AXMAP_PROGS：定义生成的axmap测试程序的名称和路径
# 构建后将在t/目录下生成axmap可执行文件
T_AXMAP_OBJS = t/axmap.o
T_AXMAP_OBJS += lib/lfsr.o lib/axmap.o
T_AXMAP_PROGS = t/axmap

# LFSR（Linear Feedback Shift Register，线性反馈移位寄存器）是一种用于生成伪随机序列的电路或算法。
# 在 fio 项目中，LFSR 被用于生成磁盘 I/O 测试中的随机偏移量，具有以下特点：
# 确定性：相同的种子产生相同的序列
# 长周期：理论上可达 (2^n - 1)（n 为寄存器位数）
# 高效性：计算复杂度低，适合高频率调用
# 均匀分布：生成的序列在周期内均匀分布
# T_LFSR_TEST_OBJS：定义构建LFSR测试程序所需的目标文件列表
# t/lfsr-test.o：LFSR测试程序的主源文件
# 依赖模块说明：
# lib/lfsr.o：LFSR算法的核心实现
# gettime.o：时间获取功能，用于性能测量
# fio_sem.o：信号量实现，用于线程同步
# pshared.o：进程间共享功能
# t/log.o：日志输出功能
# t/debug.o：调试功能
# t/arch.o：架构相关功能
# T_LFSR_TEST_PROGS：定义生成的LFSR测试程序的名称
T_LFSR_TEST_OBJS = t/lfsr-test.o
T_LFSR_TEST_OBJS += lib/lfsr.o gettime.o fio_sem.o pshared.o \
		    t/log.o t/debug.o t/arch.o
T_LFSR_TEST_PROGS = t/lfsr-test

# 随机数生成测试程序配置
# 该测试程序用于测试fio的随机数生成功能
# T_GEN_RAND_OBJS：定义构建随机数生成测试程序所需的目标文件列表
# t/gen-rand.o：随机数生成测试程序的主源文件
# 依赖模块说明：
# t/log.o：日志输出功能
# t/debug.o：调试功能
# lib/rand.o：随机数生成算法实现
# lib/pattern.o：模式生成功能
# lib/strntol.o：字符串转长整型功能
# oslib/strcasestr.o：大小写不敏感字符串查找功能
# oslib/strndup.o：字符串复制功能
# T_GEN_RAND_PROGS：定义生成的随机数生成测试程序的名称
T_GEN_RAND_OBJS = t/gen-rand.o
T_GEN_RAND_OBJS += t/log.o t/debug.o lib/rand.o lib/pattern.o lib/strntol.o \
			oslib/strcasestr.o oslib/strndup.o
T_GEN_RAND_PROGS = t/gen-rand

# Linux系统特有测试程序：btrace转fio格式测试
# 该测试程序用于将blktrace输出转换为fio可执行的测试格式
# 仅在Linux系统下构建（通过CONFIG_TARGET_OS条件判断）
# T_BTRACE_FIO_OBJS：定义构建btrace2fio测试程序所需的目标文件列表
# t/btrace2fio.o：btrace2fio测试程序的主源文件
# 依赖模块说明：
# fifo.o：FIFO队列实现
# lib/flist_sort.o：快速列表排序功能
# t/log.o：日志输出功能
# oslib/linux-dev-lookup.o：Linux设备查找功能
# T_BTRACE_FIO_PROGS：定义生成的btrace2fio测试程序的名称
ifeq ($(CONFIG_TARGET_OS), Linux)
T_BTRACE_FIO_OBJS = t/btrace2fio.o
T_BTRACE_FIO_OBJS += fifo.o lib/flist_sort.o t/log.o oslib/linux-dev-lookup.o
T_BTRACE_FIO_PROGS = t/fio-btrace2fio
endif

# 数据去重测试程序配置
# 该测试程序用于测试fio的数据去重功能，模拟存储系统中的重复数据删除
# T_DEDUPE_OBJS：定义构建数据去重测试程序所需的目标文件列表
# t/dedupe.o：数据去重测试程序的主源文件
# 依赖模块说明：
# lib/rbtree.o：红黑树数据结构实现，用于高效存储和检索
# t/log.o：日志输出功能
# fio_sem.o：信号量实现，用于线程同步
# pshared.o：进程间共享功能
# smalloc.o：自定义内存分配器实现
# gettime.o：时间获取功能
# crc/md5.o：MD5哈希算法实现，用于数据指纹生成
# lib/memalign.o：内存对齐分配功能
# lib/bloom.o：布隆过滤器实现，用于快速判断数据是否可能存在
# t/debug.o：调试功能
# crc/xxhash.o：XXHash哈希算法实现
# t/arch.o：架构相关功能
# crc/murmur3.o：Murmur3哈希算法实现
# crc/crc32c.o：CRC32C校验算法实现
# crc/crc32c-intel.o：Intel硬件加速的CRC32C实现
# crc/crc32c-arm64.o：ARM64硬件加速的CRC32C实现
# crc/fnv.o：FNV哈希算法实现
# T_DEDUPE_PROGS：定义生成的数据去重测试程序的名称
T_DEDUPE_OBJS = t/dedupe.o
T_DEDUPE_OBJS += lib/rbtree.o t/log.o fio_sem.o pshared.o smalloc.o gettime.o \
		crc/md5.o lib/memalign.o lib/bloom.o t/debug.o crc/xxhash.o \
		t/arch.o crc/murmur3.o crc/crc32c.o crc/crc32c-intel.o \
		crc/crc32c-arm64.o crc/fnv.o
T_DEDUPE_PROGS = t/fio-dedupe

# 验证状态测试程序配置
# 该测试程序用于测试fio的数据验证状态管理功能
# T_VS_OBJS：定义构建验证状态测试程序所需的目标文件列表
# t/verify-state.o：验证状态测试程序的主源文件
# 依赖模块说明：
# t/log.o：日志输出功能
# crc/crc32c.o：CRC32C校验算法实现
# crc/crc32c-intel.o：Intel硬件加速的CRC32C实现
# crc/crc32c-arm64.o：ARM64硬件加速的CRC32C实现
# t/debug.o：调试功能
# T_VS_PROGS：定义生成的验证状态测试程序的名称
T_VS_OBJS = t/verify-state.o t/log.o crc/crc32c.o crc/crc32c-intel.o crc/crc32c-arm64.o t/debug.o
T_VS_PROGS = t/fio-verify-state

# 异步管道读取测试程序配置
# 该测试程序用于测试异步管道读取功能
# T_PIPE_ASYNC_OBJS：定义构建异步管道读取测试程序所需的目标文件列表
# t/read-to-pipe-async.o：异步管道读取测试程序的主源文件
# 依赖模块说明：
# t/log.o：日志输出功能
# T_PIPE_ASYNC_PROGS：定义生成的异步管道读取测试程序的名称
T_PIPE_ASYNC_OBJS = t/read-to-pipe-async.o t/log.o
T_PIPE_ASYNC_PROGS = t/read-to-pipe-async

# io_uring测试程序配置
# 该测试程序用于测试Linux io_uring异步I/O功能
# T_IOU_RING_OBJS：定义构建io_uring测试程序所需的目标文件列表
# t/io_uring.o：io_uring测试程序的主源文件
# 依赖模块说明：
# lib/rand.o：随机数生成算法实现
# lib/pattern.o：模式生成功能
# lib/strntol.o：字符串转长整型功能
# T_IOU_RING_PROGS：定义生成的io_uring测试程序的名称
T_IOU_RING_OBJS = t/io_uring.o lib/rand.o lib/pattern.o lib/strntol.o
T_IOU_RING_PROGS = t/io_uring

# 内存锁定测试程序配置
# 该测试程序用于测试内存锁定功能
# T_MEMLOCK_OBJS：定义构建内存锁定测试程序所需的目标文件列表
# t/memlock.o：内存锁定测试程序的主源文件
# T_MEMLOCK_PROGS：定义生成的内存锁定测试程序的名称
T_MEMLOCK_OBJS = t/memlock.o
T_MEMLOCK_PROGS = t/memlock

# 时间测试程序配置
# 该测试程序用于测试时间获取和处理功能
# T_TT_OBJS：定义构建时间测试程序所需的目标文件列表
# t/time-test.o：时间测试程序的主源文件
# T_TT_PROGS：定义生成的时间测试程序的名称
T_TT_OBJS = t/time-test.o
T_TT_PROGS = t/time-test

# ==========================================
# 模糊测试（Fuzz Testing）配置部分
# ==========================================
# 检查CFLAGS中是否包含模糊测试模式宏，以决定是否构建模糊测试程序
# 模糊测试是一种自动化测试技术，通过向程序输入随机或半随机数据来发现潜在的漏洞
# 定义模糊测试目标文件列表
# t/fuzz/fuzz_parseini.o：模糊测试主程序，用于测试fio的ini配置文件解析功能
# 添加fio的核心对象文件，使模糊测试能够访问完整的fio功能
# 如果配置了算术表达式支持，则添加lex和yacc生成的解析器对象文件
# 如果未定义LIB_FUZZING_ENGINE环境变量，则添加简单的模糊驱动程序
# t/fuzz/onefile.o：读取测试文件并调用模糊测试入口函数
# 定义生成的模糊测试程序名称
# 如果未启用模糊测试模式，则将相关变量设为空
# CFLAGS不包含-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION宏
ifneq (,$(findstring -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION,$(CFLAGS)))
T_FUZZ_OBJS = t/fuzz/fuzz_parseini.o
T_FUZZ_OBJS += $(OBJS)
ifdef CONFIG_ARITHMETIC
T_FUZZ_OBJS += lex.yy.o y.tab.o
endif
# For proper fio code teardown CFLAGS needs to include -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
# in case there is no fuzz driver defined by environment variable LIB_FUZZING_ENGINE, use a simple one
# For instance, with compiler clang, address sanitizer and libFuzzer as a fuzzing engine, you should define
# export CFLAGS="-fsanitize=address,fuzzer-no-link -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
# export LIB_FUZZING_ENGINE="-fsanitize=address"
# export CC=clang
# before running configure && make
# You can adapt this with different compilers, sanitizers, and fuzzing engines
# 模糊测试环境配置说明：
# 1. 必须在CFLAGS中包含-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION宏，确保正确的资源清理
# 2. 可以通过LIB_FUZZING_ENGINE环境变量指定模糊测试引擎（如libFuzzer、AFL等）
# 3. 如果未指定模糊测试引擎，则使用内置的简单驱动程序
#
# 配置示例（使用clang和libFuzzer）：
# export CFLAGS="-fsanitize=address,fuzzer-no-link -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
# export LIB_FUZZING_ENGINE="-fsanitize=address"
# export CC=clang
# ./configure && make

ifndef LIB_FUZZING_ENGINE
T_FUZZ_OBJS += t/fuzz/onefile.o
endif
T_FUZZ_PROGS = t/fuzz/fuzz_parseini
else	# CFLAGS includes -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
T_FUZZ_OBJS =
T_FUZZ_PROGS =
endif

# ==========================================
# 测试目标文件汇总
# ==========================================
# 将所有测试程序的目标文件汇总到T_OBJS变量中，便于统一管理和构建
T_OBJS = $(T_SMALLOC_OBJS)
T_OBJS += $(T_IEEE_OBJS)
T_OBJS += $(T_ZIPF_OBJS)
T_OBJS += $(T_AXMAP_OBJS)
T_OBJS += $(T_LFSR_TEST_OBJS)
T_OBJS += $(T_GEN_RAND_OBJS)
T_OBJS += $(T_BTRACE_FIO_OBJS)
T_OBJS += $(T_DEDUPE_OBJS)
T_OBJS += $(T_VS_OBJS)
T_OBJS += $(T_PIPE_ASYNC_OBJS)
T_OBJS += $(T_MEMLOCK_OBJS)
T_OBJS += $(T_TT_OBJS)
T_OBJS += $(T_IOU_RING_OBJS)
T_OBJS += $(T_FUZZ_OBJS)

# ==========================================
# Cygwin系统特定配置
# ==========================================
# 在Cygwin系统下，为特定测试程序添加Windows相关目标文件
# 数据去重测试添加Windows目标文件
# 内存分配器测试添加Windows目标文件
# LFSR测试添加Windows目标文件
ifneq (,$(findstring CYGWIN,$(CONFIG_TARGET_OS)))
    T_DEDUPE_OBJS += $(WINDOWS_OBJS)
    T_SMALLOC_OBJS += $(WINDOWS_OBJS)
    T_LFSR_TEST_OBJS += $(WINDOWS_OBJS)
endif

# ==========================================
# 测试程序汇总
# ==========================================
# 将所有测试程序汇总到T_TEST_PROGS或T_PROGS变量中，便于统一构建和安装
T_TEST_PROGS = $(T_SMALLOC_PROGS)
T_TEST_PROGS += $(T_IEEE_PROGS)
T_PROGS += $(T_ZIPF_PROGS)
T_TEST_PROGS += $(T_AXMAP_PROGS)
T_TEST_PROGS += $(T_LFSR_TEST_PROGS)
T_TEST_PROGS += $(T_GEN_RAND_PROGS)
T_PROGS += $(T_BTRACE_FIO_PROGS)

# ==========================================
# 测试程序分类汇总
# ==========================================
# 根据测试程序的性质和依赖条件，将其分别添加到不同的程序列表中

# 数据去重测试程序：需要zlib压缩库支持
# 仅当CONFIG_ZLIB配置为真时才添加到主程序列表
ifdef CONFIG_ZLIB
T_PROGS += $(T_DEDUPE_PROGS)
endif

# 验证状态测试程序：添加到主程序列表
T_PROGS += $(T_VS_PROGS)
# 内存锁定测试程序：添加到测试程序列表
T_TEST_PROGS += $(T_MEMLOCK_PROGS)
# 异步管道读取测试程序：需要pread系统调用支持
# 仅当CONFIG_PREAD配置为真时才添加到测试程序列表
ifdef CONFIG_PREAD
T_TEST_PROGS += $(T_PIPE_ASYNC_PROGS)
endif
# io_uring异步I/O测试程序：仅适用于Linux系统
# 仅当目标操作系统是Linux时才添加到测试程序列表
ifneq (,$(findstring Linux,$(CONFIG_TARGET_OS)))
T_TEST_PROGS += $(T_IOU_RING_PROGS)
endif
# 模糊测试程序：添加到测试程序列表（条件编译，仅当启用模糊测试时有效）
T_TEST_PROGS += $(T_FUZZ_PROGS)

# ==========================================
# 主程序列表更新
# ==========================================
# 将所有测试程序添加到主程序列表中，确保它们能被统一构建和安装
PROGS += $(T_PROGS)

# ==========================================
# CUnit单元测试配置
# ==========================================
# 仅当系统支持CUnit测试框架时(CONFIG_HAVE_CUNIT宏已定义)才配置单元测试
# UT_OBJS: 单元测试程序自身所需的目标文件列表
# 包含测试框架和各个测试模块的实现文件
ifdef CONFIG_HAVE_CUNIT
UT_OBJS = unittests/unittest.o	# 单元测试主程序目标文件
UT_OBJS += unittests/lib/memalign.o	# memalign函数的单元测试实现
UT_OBJS += unittests/lib/num2str.o	# num2str函数的单元测试实现
UT_OBJS += unittests/lib/strntol.o	 # strntol函数的单元测试实现
UT_OBJS += unittests/lib/pcbuf.o	# pcbuf缓冲区的单元测试实现
UT_OBJS += unittests/oslib/strlcat.o	# strlcat函数的单元测试实现
UT_OBJS += unittests/oslib/strndup.o	# strndup函数的单元测试实现
UT_OBJS += unittests/oslib/strcasestr.o	# strcasestr函数的单元测试实现
UT_OBJS += unittests/oslib/strsep.o	# strsep函数的单元测试实现
# UT_TARGET_OBJS: 被测试的目标文件列表
# 这些是实际应用代码中的目标文件，将被单元测试程序调用和验证
UT_TARGET_OBJS = lib/memalign.o	# memalign函数的目标文件
UT_TARGET_OBJS += lib/num2str.o	# num2str函数的目标文件
UT_TARGET_OBJS += lib/strntol.o	# strntol函数的目标文件
UT_TARGET_OBJS += oslib/strlcat.o	# strlcat函数的目标文件
UT_TARGET_OBJS += oslib/strndup.o	# strndup函数的目标文件
UT_TARGET_OBJS += oslib/strcasestr.o	# strcasestr函数的目标文件
UT_TARGET_OBJS += oslib/strsep.o	# strsep函数的目标文件
# UT_PROGS: 单元测试程序的名称
UT_PROGS = unittests/unittest
else	# 当系统不支持CUnit测试框架时，清空所有单元测试相关变量
UT_OBJS =
UT_TARGET_OBJS =
UT_PROGS =
endif

# ==========================================
# 构建过程输出控制配置
# ==========================================
# 检查MAKEFLAGS中是否包含's'标志（silent模式）
# 如果没有设置silent模式，则继续配置构建过程的输出信息
ifneq ($(findstring $(MAKEFLAGS),s),s)
# 检查是否定义了V变量（详细模式）
# 如果没有定义V变量（即默认使用简洁输出），则设置静默编译标志
# QUIET_CC: 编译C文件时的静默输出标志
# 显示 "   CC [目标文件]" 后执行实际的编译命令
# QUIET_LINK: 链接目标文件时的静默输出标志
# 显示 " LINK [目标文件]" 后执行实际的链接命令
# QUIET_DEP: 生成依赖文件时的静默输出标志
# 显示 "  DEP [目标文件]" 后执行实际的依赖生成命令
# QUIET_YACC: 使用YACC生成解析器时的静默输出标志
# 显示 " YACC [目标文件]" 后执行实际的YACC命令
# QUIET_LEX: 使用LEX生成词法分析器时的静默输出标志
# 显示 "  LEX [目标文件]" 后执行实际的LEX命令
ifndef V
	QUIET_CC	= @echo '   ' CC $@;
	QUIET_LINK	= @echo ' ' LINK $@;
	QUIET_DEP	= @echo '  ' DEP $@;
	QUIET_YACC	= @echo ' ' YACC $@;
	QUIET_LEX	= @echo '  ' LEX $@;
endif
endif

# ==========================================
# 安装命令和路径配置
# ==========================================
# 根据目标操作系统选择合适的安装命令
# SunOS系统使用ginstall命令，其他系统使用标准的install命令
ifeq ($(CONFIG_TARGET_OS), SunOS)
	INSTALL = ginstall
else
	INSTALL = install
endif
# 设置安装路径前缀，默认由INSTALL_PREFIX环境变量指定（通常为/usr/local）
prefix = $(INSTALL_PREFIX)
bindir = $(prefix)/bin	# 二进制文件安装目录：前缀/bin
libdir = $(prefix)/lib/fio	# 库文件安装目录：前缀/lib/fio
mandir = $(prefix)/share/man	# 手册页安装目录：前缀/share/man
sharedir = $(prefix)/share/fio	# 共享文件安装目录：前缀/share/fio

# ==========================================
# 主构建目标
# ==========================================
# 定义all目标，依赖于所有需要构建的组件
# - PROGS：主要可执行程序
# - T_TEST_PROGS：测试程序
# - UT_PROGS：单元测试程序
# - SCRIPTS：脚本文件
# - ENGS_OBJS：动态链接的I/O引擎
all: $(PROGS) $(T_TEST_PROGS) $(UT_PROGS) $(SCRIPTS) $(ENGS_OBJS) FORCE

# ==========================================
# 伪目标声明
# ==========================================
# 声明这些目标为伪目标，不对应实际文件
# 确保即使存在同名文件，这些目标也会被执行
.PHONY: all install clean test
# FORCE是Makefile中非常常见的伪目标，主要用于：
# 强制其他目标重新构建
# 作为依赖项添加到需要总是重新执行的目标中
.PHONY: FORCE cscope

# ==========================================
# C源文件通用编译规则
# ==========================================
# %.o : %.c - 通用模式规则：将任何.c文件编译为对应的.o文件
# $@ - 目标文件（%.o）
# $< - 依赖文件（%.c）
# $* - 匹配的文件名前缀（不包含扩展名）
%.o : %.c
# 	确保输出目录存在，如果不存在则创建
	@mkdir -p $(dir $@)
# 	编译C源文件生成目标文件
# 	$(QUIET_CC) - 静默编译标志（如果定义了则显示编译信息）
# 	$(CC) - C编译器
# 	-o $@ - 指定输出文件
# 	$(CFLAGS) $(CPPFLAGS) - 编译器和预处理器选项
# 	-c - 只编译不链接
# 	$< - 输入的C源文件
	$(QUIET_CC)$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) -c $<
# 	生成依赖文件（.d文件）
# 	-MM - 生成依赖关系（不包含系统头文件）
# 	$(SRCDIR)/$*.c - 源文件的完整路径
# 	> $*.d - 将输出重定向到.d文件
	@$(CC) -MM $(CFLAGS) $(CPPFLAGS) $(SRCDIR)/$*.c > $*.d
# 	将生成的依赖文件重命名为临时文件，用于后续处理
	@mv -f $*.d $*.d.tmp
# 	处理临时依赖文件：将依赖项的目标改为当前的.o文件
# 	sed -e 's|.*:|$*.o:|' - 将行首的所有内容替换为$*.o:
# 	< $*.d.tmp - 输入临时依赖文件
# 	> $*.d - 输出到最终的.d文件
	@sed -e 's|.*:|$*.o:|' < $*.d.tmp > $*.d
# 	如果系统有fmt命令，用于格式化依赖关系，否则使用默认格式化
# 	如果有fmt命令：使用fmt格式化依赖项列表，确保每行一个依赖项
# 	如果没有fmt命令：使用tr和sed实现类似功能
# 	sed -e 's/.*://' -e 's/\\$$//' - 提取依赖项并移除换行符
# 	tr -cs "[:graph:]" "\n" - 将非图形字符替换为换行符
# 	sed -e 's/^ *//' -e '/^$$/ d' -e 's/$$/:/' - 清理空格，删除空行，添加冒号
	@if type -p fmt >/dev/null 2>&1; then				\
		sed -e 's/.*://' -e 's/\\$$//' < $*.d.tmp | fmt -w 1 |	\
		sed -e 's/^ *//' -e 's/$$/:/' >> $*.d;			\
	else								\
		sed -e 's/.*://' -e 's/\\$$//' < $*.d.tmp |		\
		tr -cs "[:graph:]" "\n" |				\
		sed -e 's/^ *//' -e '/^$$/ d' -e 's/$$/:/' >> $*.d;	\
	fi
# 	删除临时依赖文件
	@rm -f $*.d.tmp

# ==========================================
# 词法分析器编译规则（条件编译）
# ==========================================
# 仅当启用算术表达式支持时（CONFIG_ARITHMETIC宏已定义）
# 才编译词法分析器
# 目标：lex.yy.c - 词法分析器生成的C源文件
# 依赖：exp/expression-parser.l - 词法分析器定义文件(.l文件)
# 使用LEX工具将.l文件转换为C源文件
ifdef CONFIG_ARITHMETIC
lex.yy.c: exp/expression-parser.l
# 检查是否需要使用-o参数明确指定输出文件
# CONFIG_LEX_USE_O宏控制LEX命令的调用方式
ifdef CONFIG_LEX_USE_O
# 如果需要使用-o参数：
# $(QUIET_LEX) - 静默输出标志（如果定义了则显示"LEX lex.yy.c"）
# $(LEX) - LEX工具（通常是flex）
# -o $@ - 指定输出文件为$@（即lex.yy.c）
# $< - 输入文件（即exp/expression-parser.l）
	$(QUIET_LEX)$(LEX) -o $@ $<
else
# 如果不需要使用-o参数：直接调用LEX工具
# LEX工具默认会生成lex.yy.c作为输出文件
	$(QUIET_LEX)$(LEX) $<
endif

# ==========================================
# 词法/语法分析器特殊编译标志配置
# ==========================================
# 条件判断：检查CFLAGS中是否包含-Wimplicit-fallthrough警告标志
# 该警告用于检测switch语句中的隐式fallthrough情况
# 如果包含该警告标志，为词法分析器生成的文件设置特殊编译标志
# LEX_YY_CFLAGS: lex.yy.c文件的特殊编译标志
# -Wno-implicit-fallthrough: 禁用隐式fallthrough警告
# 原因：lex生成的词法分析器代码中会大量使用隐式fallthrough，这些是正常的设计模式
ifneq (,$(findstring -Wimplicit-fallthrough,$(CFLAGS)))
LEX_YY_CFLAGS := -Wno-implicit-fallthrough
endif

# 条件判断：检查是否定义了CONFIG_HAVE_NO_STRINGOP宏
# 该宏通常在支持更严格字符串操作检查的编译器上定义
# 如果定义了该宏，为语法分析器生成的文件设置特殊编译标志
# YTAB_YY_CFLAGS: y.tab.c文件的特殊编译标志
# -Wno-stringop-truncation: 禁用字符串操作截断警告
# 原因：yacc/bison生成的语法分析器代码中会出现合法的字符串截断操作
ifdef CONFIG_HAVE_NO_STRINGOP
YTAB_YY_CFLAGS := -Wno-stringop-truncation
endif

# ==========================================
# 词法分析器和语法分析器的编译规则
# ==========================================

# 目标：lex.yy.o - 词法分析器的目标文件
# 依赖：lex.yy.c - 词法分析器生成的C源文件
#       y.tab.h - 语法分析器生成的头文件
# 命令：编译lex.yy.c生成目标文件，包含词法分析器特殊编译标志
# $(QUIET_CC) - 静默编译标志（如果定义了则显示"CC lex.yy.o"）
# $(CC) - C编译器
# -o $@ - 指定输出文件为$@（即lex.yy.o）
# $(CFLAGS) $(CPPFLAGS) - 标准编译器和预处理器选项
# $(LEX_YY_CFLAGS) - 词法分析器特殊编译标志（如-Wno-implicit-fallthrough）
# -c - 只编译不链接
# $< - 输入文件（即lex.yy.c）
lex.yy.o: lex.yy.c y.tab.h
	$(QUIET_CC)$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(LEX_YY_CFLAGS) -c $<

# 目标：y.tab.o - 语法分析器的目标文件
# 依赖：y.tab.c - 语法分析器生成的C源文件
#       y.tab.h - 语法分析器生成的头文件
# 命令：编译y.tab.c生成目标文件，包含语法分析器特殊编译标志
# $(QUIET_CC) - 静默编译标志（如果定义了则显示"CC y.tab.o"）
# $(CC) - C编译器
# -o $@ - 指定输出文件为$@（即y.tab.o）
# $(CFLAGS) $(CPPFLAGS) - 标准编译器和预处理器选项
# $(YTAB_YY_CFLAGS) - 语法分析器特殊编译标志（如-Wno-stringop-truncation）
# -c - 只编译不链接
# $< - 输入文件（即y.tab.c）
y.tab.o: y.tab.c y.tab.h
	$(QUIET_CC)$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) $(YTAB_YY_CFLAGS) -c $<

# 目标：y.tab.c - 语法分析器生成的C源文件
# 依赖：exp/expression-parser.y - 语法分析器定义文件(.y文件)
# 命令：使用YACC工具将.y文件转换为C源文件和头文件
# $(QUIET_YACC) - 静默输出标志（如果定义了则显示"YACC y.tab.c"）
# $(YACC) - YACC工具（通常是bison）
# -o $@ - 指定输出文件为$@（即y.tab.c）
# -l - 使用bison的标准头文件（不生成位置信息）
# -d - 同时生成头文件（y.tab.h）
# -b y - 设置输出文件的基础名称为"y"（生成y.tab.c和y.tab.h）
# $< - 输入文件（即exp/expression-parser.y）
y.tab.c: exp/expression-parser.y
	$(QUIET_YACC)$(YACC) -o $@ -l -d -b y $<

# 目标：y.tab.h - 语法分析器生成的头文件
# 依赖：y.tab.c - 语法分析器生成的C源文件
# 说明：y.tab.h是由y.tab.c的生成命令自动生成的，
#       这个规则确保y.tab.h的依赖关系被正确跟踪
y.tab.h: y.tab.c

# 目标：lexer.h - 词法分析器头文件
# 依赖：lex.yy.c - 词法分析器生成的C源文件
# 说明：lexer.h是由lex.yy.c的生成命令自动生成的，
#       这个规则确保lexer.h的依赖关系被正确跟踪
lexer.h: lex.yy.c

# ==========================================
# 表达式解析器测试程序的编译和链接规则
# ==========================================

# 目标：exp/test-expression-parser.o - 表达式解析器测试程序的目标文件
# 依赖：exp/test-expression-parser.c - 表达式解析器测试程序的源文件
# 编译测试程序源文件生成目标文件
# $(QUIET_CC) - 静默编译标志（如果定义了则显示"CC exp/test-expression-parser.o"）
# $(CC) - C编译器
# -o $@ - 指定输出文件为$@（即exp/test-expression-parser.o）
# $(CFLAGS) $(CPPFLAGS) - 编译器和预处理器选项
# -c - 只编译不链接
# $< - 输入文件（即exp/test-expression-parser.c）
exp/test-expression-parser.o: exp/test-expression-parser.c
	$(QUIET_CC)$(CC) -o $@ $(CFLAGS) $(CPPFLAGS) -c $<
# 目标：exp/test-expression-parser - 表达式解析器测试程序的可执行文件
# 依赖：exp/test-expression-parser.o - 测试程序的目标文件
# 链接测试程序与表达式解析器组件
# $(QUIET_LINK) - 静默链接标志（如果定义了则显示"LINK exp/test-expression-parser"）
# $(CC) - C编译器（用于链接）
# $(LDFLAGS) - 链接器选项
# $< - 输入文件（即exp/test-expression-parser.o）
# y.tab.o lex.yy.o - 语法分析器和词法分析器的目标文件
# -o $@ - 指定输出文件为$@（即exp/test-expression-parser）
# $(LIBS) - 链接的库文件
exp/test-expression-parser: exp/test-expression-parser.o
	$(QUIET_LINK)$(CC) $(LDFLAGS) $< y.tab.o lex.yy.o -o $@ $(LIBS)

# ==========================================
# 解析器目标文件的依赖关系
# ==========================================
# 目标：parse.o - 解析器的目标文件
# 依赖：lex.yy.o - 词法分析器的目标文件
#       y.tab.o - 语法分析器的目标文件
# 说明：parse.o依赖于词法和语法分析器组件，
#       当这些组件更新时，parse.o会被重新编译
parse.o: lex.yy.o y.tab.o
endif

# ==========================================
# 特定源文件的编译规则
# ==========================================

# init.o的依赖关系：除了init.c，还依赖FIO-VERSION-FILE
# 当版本文件更新时，init.o会被重新编译
init.o: init.c FIO-VERSION-FILE

# ==========================================
# GTK图形界面相关文件的编译规则
# ==========================================
# 这些文件需要GTK库支持，因此编译时添加$(GTK_CFLAGS)

# gcompat.o - GTK兼容性支持
gcompat.o: gcompat.c gcompat.h
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<
# goptions.o - GTK选项处理
goptions.o: goptions.c goptions.h
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<
# ghelpers.o - GTK辅助函数
ghelpers.o: ghelpers.c ghelpers.h
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<
# gerror.o - GTK错误处理
gerror.o: gerror.c gerror.h
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<
# gclient.o - GTK客户端
gclient.o: gclient.c gclient.h
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<
# gfio.o - GTK界面主程序
gfio.o: gfio.c ghelpers.c
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<
# graph.o - 图形绘制
graph.o: graph.c graph.h
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<
# cairo_text_helpers.o - Cairo文本渲染辅助
cairo_text_helpers.o: cairo_text_helpers.c cairo_text_helpers.h
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<
# printing.o - 打印功能
printing.o: printing.c printing.h
	$(QUIET_CC)$(CC) $(CFLAGS) $(GTK_CFLAGS) $(CPPFLAGS) -c $<

# ==========================================
# 测试程序的链接规则
# ==========================================

# t/io_uring.o的依赖关系：依赖Linux的io_uring头文件
t/io_uring.o: os/linux/io_uring.h
# t/io_uring - io_uring异步I/O测试程序
t/io_uring: $(T_IOU_RING_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_IOU_RING_OBJS) $(LIBS)
# t/read-to-pipe-async - 异步管道读取测试程序
t/read-to-pipe-async: $(T_PIPE_ASYNC_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_PIPE_ASYNC_OBJS) $(LIBS)
# t/memlock - 内存锁定测试程序
t/memlock: $(T_MEMLOCK_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_MEMLOCK_OBJS) $(LIBS)
# t/stest - smalloc内存分配器测试程序
t/stest: $(T_SMALLOC_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_SMALLOC_OBJS) $(LIBS)
# t/ieee754 - IEEE754浮点数测试程序
t/ieee754: $(T_IEEE_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_IEEE_OBJS) $(LIBS)

# ==========================================
# 主程序的链接规则
# ==========================================
# fio - 主程序
fio: $(FIO_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(FIO_OBJS) $(LIBS) $(HDFSLIB)

# ==========================================
# 模糊测试程序的链接规则
# ==========================================

# t/fuzz/fuzz_parseini - INI解析器模糊测试程序
t/fuzz/fuzz_parseini: $(T_FUZZ_OBJS)
# 条件判断：是否使用外部模糊测试引擎
# 不使用外部引擎时的链接方式
# 使用外部引擎(LIB_FUZZING_ENGINE)时的链接方式
# 使用CXX编译，因为libFuzzer等引擎通常是C++实现
ifndef LIB_FUZZING_ENGINE
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_FUZZ_OBJS) $(LIBS) $(HDFSLIB)
else
	$(QUIET_LINK)$(CXX) $(LDFLAGS) -o $@ $(T_FUZZ_OBJS) $(LIB_FUZZING_ENGINE) $(LIBS) $(HDFSLIB)
endif

# ==========================================
# GTK图形界面程序的链接规则
# ==========================================

# gfio - 图形界面程序
# $(filter-out -static, $(LDFLAGS)) - 从LDFLAGS中移除-static选项（GTK通常不支持静态链接）
gfio: $(GFIO_OBJS)
	$(QUIET_LINK)$(CC) $(filter-out -static, $(LDFLAGS)) -o gfio $(GFIO_OBJS) $(LIBS) $(GFIO_LIBS) $(GTK_LDFLAGS) $(HDFSLIB)

# ==========================================
# 其他测试程序的链接规则
# ==========================================

# t/fio-genzipf - Zipf分布生成器
t/fio-genzipf: $(T_ZIPF_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_ZIPF_OBJS) $(LIBS)
# t/axmap - 轴映射测试程序
t/axmap: $(T_AXMAP_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_AXMAP_OBJS) $(LIBS)
# t/lfsr-test - LFSR(线性反馈移位寄存器)测试程序
t/lfsr-test: $(T_LFSR_TEST_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_LFSR_TEST_OBJS) $(LIBS)
# t/gen-rand - 随机数生成测试程序
t/gen-rand: $(T_GEN_RAND_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_GEN_RAND_OBJS) $(LIBS)

# ==========================================
# 条件测试程序的链接规则
# ==========================================

# t/fio-btrace2fio - blktrace转换工具，仅在Linux上可用
ifeq ($(CONFIG_TARGET_OS), Linux)
t/fio-btrace2fio: $(T_BTRACE_FIO_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_BTRACE_FIO_OBJS) $(LIBS)
endif

# t/fio-dedupe - 数据去重测试程序，仅在支持zlib时可用
ifdef CONFIG_ZLIB
t/fio-dedupe: $(T_DEDUPE_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_DEDUPE_OBJS) $(LIBS)
endif

# t/fio-verify-state - 验证状态测试程序
t/fio-verify-state: $(T_VS_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_VS_OBJS) $(LIBS)
# t/time-test - 时间测试程序
t/time-test: $(T_TT_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(T_TT_OBJS) $(LIBS)

# ==========================================
# 单元测试程序的链接规则
# ==========================================

# unittests/unittest - CUnit单元测试程序，仅在支持CUnit时可用
# -lcunit - 链接CUnit测试框架库
ifdef CONFIG_HAVE_CUNIT
unittests/unittest: $(UT_OBJS) $(UT_TARGET_OBJS)
	$(QUIET_LINK)$(CC) $(LDFLAGS) -o $@ $(UT_OBJS) $(UT_TARGET_OBJS) -lcunit $(LIBS)
endif

# ==========================================
# 清理目标
# ==========================================

# clean - 清理构建生成的文件
# 删除依赖文件、目标文件、程序和临时文件
# 删除特定的测试程序
# 删除文档输出目录
# 递归清理mock-tests目录
clean: FORCE
	@rm -f .depend $(FIO_OBJS) $(GFIO_OBJS) $(OBJS) $(T_OBJS) $(UT_OBJS) $(PROGS) $(T_PROGS) $(T_TEST_PROGS) core.* core gfio unittests/unittest FIO-VERSION-FILE *.[do] lib/*.d oslib/*.[do] crc/*.d engines/*.[do] engines/*.so profiles/*.[do] t/*.[do] t/*/*.[do] unittests/*.[do] unittests/*/*.[do] config-host.mak config-host.h y.tab.[ch] lex.yy.c exp/*.[do] lexer.h
	@rm -f t/fio-btrace2fio t/io_uring t/read-to-pipe-async
	@rm -rf  doc/output
	@$(MAKE) -C mock-tests clean

# distclean - 深度清理，除了clean的内容外，还清理额外文件
# 删除cscope索引文件和PDF文档
distclean: clean FORCE
	@rm -f cscope.out fio.pdf fio_generate_plots.pdf fio2gnuplot.pdf fiologparser_hist.pdf

# ==========================================
# 代码索引生成目标
# ==========================================

# cscope - 生成cscope代码索引文件
# 用于代码浏览和搜索
# -b - 只生成索引文件，不进入交互模式
# -R - 递归处理所有子目录
cscope:
	@cscope -b -R

# ==========================================
# 手册页生成目标
# ==========================================

# tools/plot/fio2gnuplot.1 - 生成fio2gnuplot命令的手册页
# .1是Unix/Linux系统中用户命令手册页的扩展名
# 将manpage文本文件转换为man格式的手册页
# txt2man - 文本转manpage工具
# -t fio2gnuplot - 设置手册页标题
tools/plot/fio2gnuplot.1:
	@cat tools/plot/fio2gnuplot.manpage | txt2man -t fio2gnuplot >  tools/plot/fio2gnuplot.1

# ==========================================
# 文档生成目标
# ==========================================

# doc - 生成PDF格式的文档
# 依赖于tools/plot/fio2gnuplot.1手册页
# 生成fio主程序的PDF手册
# man -t - 将手册页转换为PostScript格式
# ps2pdf - 将PostScript转换为PDF格式
# 生成fio_generate_plots工具的PDF手册
# 生成fio2gnuplot工具的PDF手册
# 生成fiologparser_hist.py工具的PDF手册
doc: tools/plot/fio2gnuplot.1
	@man -t ./fio.1 | ps2pdf - fio.pdf
	@man -t tools/fio_generate_plots.1 | ps2pdf - fio_generate_plots.pdf
	@man -t tools/plot/fio2gnuplot.1 | ps2pdf - fio2gnuplot.pdf
	@man -t tools/hist/fiologparser_hist.py.1 | ps2pdf - fiologparser_hist.pdf

# ==========================================
# 测试目标
# ==========================================

# test - 运行基本的fio测试
# 依赖于fio主程序
# 运行两个测试：
# 1. nulltest - 使用null I/O引擎进行随机读写测试
#    --minimal - 输出最简洁的结果
#    --thread - 使用线程而不是进程
#    --exitall_on_error - 任何测试失败都退出
#    --runtime=1s - 运行1秒
#    --ioengine=null - 使用null I/O引擎（不执行实际I/O）
#    --rw=randrw - 随机读写模式
#    --iodepth=2 - I/O队列深度为2
#    --norandommap - 不使用随机映射
#    --random_generator=tausworthe64 - 使用tausworthe64随机数生成器
#    --size=16T - 测试大小为16TB（对于null引擎来说只是虚拟大小）
# 2. verifyfstest - 使用crc32c验证的写入测试
#    --filename=fiotestfile.tmp - 测试文件名
#    --unlink=1 - 测试完成后删除文件
#    --rw=write - 写入模式
#    --verify=crc32c - 使用crc32c验证数据完整性
#    --verify_state_save=0 - 不保存验证状态
#    --size=16K - 测试大小为16KB
test: fio
	./fio --minimal --thread --exitall_on_error --runtime=1s --name=nulltest --ioengine=null --rw=randrw --iodepth=2 --norandommap --random_generator=tausworthe64 --size=16T --name=verifyfstest --filename=fiotestfile.tmp --unlink=1 --rw=write --verify=crc32c --verify_state_save=0 --size=16K

# mock-tests - 运行mock测试
# 使用单独的mock-tests目录
# -C mock-tests - 进入mock-tests目录
# test - 运行mock-tests目录中的test目标
mock-tests:
	$(MAKE) -C mock-tests test

# fulltest - 运行完整的测试套件
# 包括null_blk模块和libzbc测试
fulltest:
# 加载null_blk内核模块（用于模拟块设备）
# 检查libzbc库是否安装
# 如果未安装，从GitHub克隆libzbc库并安装
# 运行zbd测试套件，使用null_blk模拟设备
# 检查null_blk模块是否支持zoned功能
# 如果支持，运行更多的zoned测试
	sudo modprobe null_blk &&				 	\
	if [ ! -e /usr/include/libzbc/zbc.h ]; then			\
	  git clone https://github.com/westerndigitalcorporation/libzbc && \
	  (cd libzbc &&						 	\
	   ./autogen.sh &&					 	\
	   ./configure --prefix=/usr &&				 	\
	   make -j &&						 	\
	   sudo make install)						\
	fi &&					 			\
	sudo t/zbd/run-tests-against-nullb -s 1 &&		 	\
	if [ -e /sys/module/null_blk/parameters/zoned ]; then		\
		sudo t/zbd/run-tests-against-nullb -s 2;	 	\
		sudo t/zbd/run-tests-against-nullb -s 4;	 	\
	fi

# ==========================================
# 安装目标
# ==========================================

# install - 安装fio及其相关文件
# 依赖于程序、脚本、引擎和手册页
install: $(PROGS) $(SCRIPTS) $(ENGS_OBJS) tools/plot/fio2gnuplot.1 FORCE
# 创建二进制文件安装目录
	$(INSTALL) -m 755 -d $(DESTDIR)$(bindir)
# 安装二进制文件和脚本
	$(INSTALL) $(PROGS) $(SCRIPTS) $(DESTDIR)$(bindir)
# 条件安装动态I/O引擎（如果启用了CONFIG_DYNAMIC_ENGINES）
ifdef CONFIG_DYNAMIC_ENGINES
# 创建引擎库安装目录
	$(INSTALL) -m 755 -d $(DESTDIR)$(libdir)
# 安装动态引擎库文件
	$(INSTALL) -m 755 $(SRCDIR)/engines/*.so $(DESTDIR)$(libdir)
endif
# 创建手册页安装目录
	$(INSTALL) -m 755 -d $(DESTDIR)$(mandir)/man1
# 安装主程序手册页
	$(INSTALL) -m 644 $(SRCDIR)/fio.1 $(DESTDIR)$(mandir)/man1
# 安装fio_generate_plots工具手册页
	$(INSTALL) -m 644 $(SRCDIR)/tools/fio_generate_plots.1 $(DESTDIR)$(mandir)/man1
# 安装fio2gnuplot工具手册页
	$(INSTALL) -m 644 $(SRCDIR)/tools/plot/fio2gnuplot.1 $(DESTDIR)$(mandir)/man1
# 安装fiologparser_hist.py工具手册页
	$(INSTALL) -m 644 $(SRCDIR)/tools/hist/fiologparser_hist.py.1 $(DESTDIR)$(mandir)/man1
# 创建共享文件安装目录
	$(INSTALL) -m 755 -d $(DESTDIR)$(sharedir)
# 安装gnuplot模板文件
	$(INSTALL) -m 644 $(SRCDIR)/tools/plot/*gpm $(DESTDIR)$(sharedir)/

# ==========================================
# 伪目标声明
# ==========================================

# 声明test和fulltest为伪目标
.PHONY: test fulltest
