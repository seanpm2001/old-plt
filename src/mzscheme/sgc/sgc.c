/*
  SenoraGC, a relatively portable conservative GC for a slightly
    cooperative environment
  Copyright (c) 1996-97 Matthew Flatt
  All rights reserved.

  After Boehm et al.

  Please see the full copyright in the documentation.

  This collector is intended mainly for debugging and memory tracing,
  but it can also act as a reasonbaly effecient, general-purpose
  conservative collector.

  It's probably still a little hardwired for 32-bit addresses.

  The stack base must be manually identified with GC_set_stack_base();
  no garbage collection will occur before this function is called.

  All non-stack/register roots (i.e., global variables) must be
  registered with GC_add_roots(). For certain platforms, this is
  actually done automatically for static variables, but it can't be 
  done portably in general. (See AUTO_STATIC_ROOTS_IF_POSSIBLE in
  the flags section.)

  GC space is allocated using malloc() and free(). Alternatively, the
  GC can define malloc() and free() itself if platform-specific
  allocation routines are supported.  
  
  This collector is not recommended as a replacement for Boehm's GC if
  you can get Boehm's to work at all. SenoraGC MIGHT be useful if, for
  some reason, Boehm's collector does not work for your platform.
  SenoraGC MIGHT be useful as a debugging collector if you can figure
  out the [undocumented] debugging utilities. */

#include <stdlib.h>
#include <setjmp.h>
#include <stdio.h>
#include <memory.h>
#include "../sconfig.h"
#include "sgc.h"

/****************************************************************************/
/* Option bundles                                                           */
/****************************************************************************/

#ifndef SGC_STD_DEBUGGING
# define SGC_STD_DEBUGGING 0
#endif

#ifdef WIN32
# define SGC_STD_DEBUGGING_UNIX 0
# define SGC_STD_DEBUGGING_WINDOWS SGC_STD_DEBUGGING
#else
# define SGC_STD_DEBUGGING_UNIX SGC_STD_DEBUGGING
# define SGC_STD_DEBUGGING_WINDOWS 0
#endif

/****************************************************************************/
/* Options and debugging flags                                              */
/****************************************************************************/

#define NO_COLLECTIONS 0
/* Disable all collections */

#define NO_DISAPPEARING 0
/* Never perform disappearing link */

#define NO_FINALIZING 0
/* Never invoke queued finalizers */

#define NO_ATOMIC 0
/* Never treat allocated data as atomic */

#define NO_FREE_BLOCKS 0
/* Keep small-chunk assignment of a block forever */

#define USE_BEST_FIT_ON_FREE_SECTORS 0
/* Select best-fit versus gravity-fit (which tries to
   keep all the blocks close together to avoid) */

#define NO_STACK_OFFBYONE 0
/* Don't notice a stack-based pointer just past the end of an object */

#define WATCH_FOR_FINALIZATION_CYCLES 0
/* Report cycles in finalizable chunks */

#define PROVIDE_GC_FREE 0
/* Provide GC_free; automatically implies DISTINGUISH_FREE_FROM_UNMARKED */

#define PROVIDE_MALLOC_AND_FREE SGC_STD_DEBUGGING_UNIX
/* Defines malloc(), realloc(), calloc(), and  free() in terms of 
   the collector. Platform-specific allocation routines (e.g., sbrk())
   must then be used for low-level allocations by the collector;
   turn on one of: GET_MEM_VIA_SBRK.
   This will not work if fprintf uses malloc of free. Turing on
   FPRINTF_USE_PRIM_STRINGOUT can solve this problem.
   Automatically implies PROVIDE_GC_FREE, but adds extra checks to
   CHECK_FREES if PROVIDE_GC_FREE was not otherwise on */

#define GET_MEM_VIA_SBRK SGC_STD_DEBUGGING_UNIX
/* Instead of calling malloc() to get low-level memory, use
   sbrk() directly. (Unix) */

#define GET_MEM_VIA_VIRTUAL_ALLOC SGC_STD_DEBUGGING_WINDOWS
/* Instead of calling malloc() to get low-level memory, use
   VirtualAlloc() directly. (Win32) */

#define DISTINGUISH_FREE_FROM_UNMARKED 0
/* Don't let conservatism resurrect a previously-collected block */

#define TERSE_MEMORY_TRACING 0
/* Automatically implies ALLOW_TRACE_COUNT, ALLOW_TRACE_PATH,
   ALLOW_SET_FINALIZER, and CHECK_WATCH_FOR_PTR_ALLOC */

#define STD_MEMORY_TRACING SGC_STD_DEBUGGING
/* Automatically implies TERSE_MEMORY_TRACING, DUMP_BLOCK_COUNTS,
   and DUMP_SECTOR_MAP */

#define DETAIL_MEMORY_TRACING 1
/* Automatically implies STD_MEMORY_TRACING, DUMP_BLOCK_MAPS, 
   STAMP_AND_REMEMBER_SOURCE, and KEEP_DETAIL_PATH */

#define STAMP_AND_REMEMBER_SOURCE 0
/* Keep timestamps and source of marking from collection */

#define ALLOW_TRACE_COUNT 0
/* Support collection-based trace count callbacks */

#define ALLOW_TRACE_PATH 0
/* Support collection-based trace path callbacks */

#define KEEP_DETAIL_PATH 0
/* Keep source offsets for path traces */

#define ALLOW_SET_LOCKING 0
/* Enables locking out collections for a specific set. */

#define ALLOW_SET_FINALIZER 0
/* Support the per-set custom "de-allocation" callback. */

#define CHECK_WATCH_FOR_PTR_ALLOC SGC_STD_DEBUGGING
/* Set GC_watch_for_ptr to be ~(ptr value);
   there are 3 places where the ptr is checked, 
   unless USE_WATCH_FOUND_FUNC is on */

#define USE_WATCH_FOUND_FUNC SGC_STD_DEBUGGING
/* Calls GC_found_watch when the watch-for ptr is found. */

#define PAD_BOUNDARY_BYTES 0
/* Put a known padding pattern around every allocated
   block to test for array overflow/underflow.
   Pad-testing is performed at the beginning of every GC.
   Automatically implies CHECK_SIMPLE_INTERIOR_POINTERS */

#define CHECK_SIMPLE_INTERIOR_POINTERS 0
/* Recognize pointers into the middle of an allocated
   block, (but do not recognize pointers just past the
   end of an allocated block, as is generally performed
   for stack-based pointers). */

#define DUMP_BLOCK_COUNTS SGC_STD_DEBUGGING
/* GC_dump prints detail information about block and
   set size contents. */

#define DUMP_SECTOR_MAP SGC_STD_DEBUGGING
/* GC_dump prints detail information about existing
   sectors. */

#define DUMP_BLOCK_MAPS 0
/* GC_dump prints detail information about block and
   set address contents. Automatically implies
   DUMP_BLOCK_COUNTS. */

#define CHECK_FREES SGC_STD_DEBUGGING
/* Print an error for redundant frees by calling free_error */

#define FPRINTF_USE_PRIM_STRINGOUT SGC_STD_DEBUGGING_WINDOWS
/* Avoids using fprintf while the GC is running, printing
   messages instead as pure strings passed to
    void GC_prim_stringout(char *s, int len);
   which must be provided at link time, or one of
   PRIM_STRINGOUT_AS_FWRITE or PRIM_STRINGOUT_AS_WINDOWS_CONSOLE */

#define PRIM_STRINGOUT_AS_FWRITE 0
/* Implements GC_prim_stringout using fwrite. Not likely to
   solve any problems, but useful for debugging FPRINTF. */

#define PRIM_STRINGOUT_AS_WINDOWS_CONSOLE SGC_STD_DEBUGGING_WINDOWS
/* Implements GC_prim_stringout using Windows console
   functions. */

#define AUTO_STATIC_ROOTS_IF_POSSIBLE 1
/* Automatically registers static C variables as roots if
   platform-specific code is porvided */

#define SHOW_SECTOR_MAPS_AT_GC 0
/* Write a sector map before and after each GC. This is helpful for
   noticing unusual memory pattens, such as allocations of large
   blocks or unusually repetitive allocations. */

/****************************************************************************/
/* Parameters and platform-specific settings                                */
/****************************************************************************/

/* GC frequency: MEM_USE_FACTOR is max factor between current
   allocated bytes and alocated bytes after last GC. */
#ifdef SMALL_HASH_TABLES
# define FIRST_GC_LIMIT 20000
# define MEM_USE_FACTOR 1.40
#else
# define FIRST_GC_LIMIT 100000
# define MEM_USE_FACTOR 2
#endif

#ifdef DOS_FAR_POINTERS
# include <dos.h>
# include <alloc.h>
# define PTR_TO_INT(v) (((((long)FP_SEG(v)) & 0xFFFF) << 4) + FP_OFF(v))
# define INT_TO_PTR(v) ((void *)((((v) >> 4) << 16) + ((v) & 0xF)))
# if !PROVIDE_MALLOC_AND_FREE
#  define MALLOC farmalloc
#  define FREE farfree
# endif
#else
# define PTR_TO_INT(v) ((unsigned long)(v))
# define INT_TO_PTR(v) ((void *)(v))
# if !PROVIDE_MALLOC_AND_FREE
#  define MALLOC malloc
#  define FREE free
# endif
#endif

#if GET_MEM_VIA_SBRK
# include <unistd.h>
#endif
#ifdef WIN32
# include <windows.h>
#endif

/* System-specific alignment of pointers. */
#define PTR_ALIGNMENT 4
#define LOG_PTR_SIZE 2
#define PTR_SIZE (1 << LOG_PTR_SIZE)

/* SECTOR_SEGMENT_SIZE determines the alignment of collector blocks.
   Since it should be a power of 2, LOG_SECTOR_SEGMENT_SIZE is
   specified directly. A larger block size speeds up GC, but wastes
   more unallocated bytes in same-size buckets. */
# define LOG_SECTOR_SEGMENT_SIZE 12
#define SECTOR_SEGMENT_SIZE (1 << LOG_SECTOR_SEGMENT_SIZE)
#define SECTOR_SEGMENT_MASK (~(SECTOR_SEGMENT_SIZE-1))

/* MAX_COMMON_SIZE is maximum size of allocated blocks
   using relatively efficient memory layouts. */
#define MAX_COMMON_SIZE (SECTOR_SEGMENT_SIZE >> 2)

#define NUM_COMMON_SIZE ((2 * LOG_SECTOR_SEGMENT_SIZE) + 8)

/* Number of sector segments to be allocated at once with
   malloc() to avoid waste when obtaining the proper alignment. */
#define SECTOR_SEGMENT_GROUP_SIZE 32

/* Number of bits used in first level table for checking existance of
   a sector. Creates a table of (1 << SECTOR_LOOKUP_SHIFT) pointers
   to individual page tables of size SECTOR_LOOKUP_PAGESIZE. */
#define SECTOR_LOOKUP_PAGESETBITS 12

#define SECTOR_LOOKUP_SHIFT ((PTR_SIZE*8) - SECTOR_LOOKUP_PAGESETBITS)
#define LOG_SECTOR_LOOKUP_PAGESIZE ((PTR_SIZE*8) - SECTOR_LOOKUP_PAGESETBITS - LOG_SECTOR_SEGMENT_SIZE)
#define SECTOR_LOOKUP_PAGESIZE (1 << LOG_SECTOR_LOOKUP_PAGESIZE)
#define SECTOR_LOOKUP_PAGEMASK (SECTOR_LOOKUP_PAGESIZE - 1)

#define SECTOR_LOOKUP_PAGETABLE(x) (x >> SECTOR_LOOKUP_SHIFT)
#define SECTOR_LOOKUP_PAGEPOS(x) ((x >> LOG_SECTOR_SEGMENT_SIZE) & SECTOR_LOOKUP_PAGEMASK)

#define LOG_SECTOR_PAGEREC_SIZE (LOG_PTR_SIZE + 1)

/***************************************************************************/

/* Implementation Terminology:
    "sector" - A low-level block of memory. Given an arbitrary
               pointer value, whether it is contained in a sector and
	       the starting point of the sector can be determined in
	       constant time.
    "segment" - A portion of a sector, aligned on SECTOR_SEGMENT_SIZE 
               boundaries.
    "page" - part of a table for a (partial) mapping from addresses to 
               segments
    "block" or "common block" - A block for small memory allocations. Blocks
               provide allocation by partitioning a sector.
    "chunk" - A block of memory too large to be a common block. Each chunk
               is allocated in its own sector.
    "set" - A collection of blocks & chunks asscoaited with a particular
               name, "deallocation" function, trace function, etc.
*/

/***************************************************************************/

/* Debugging the collector: */
#define CHECK 0
#define PRINT 0
#define TIME 0
#define ALWAYS_TRACE 0
#define CHECK_COLLECTING 0

#if DETAIL_MEMORY_TRACING
# undef STD_MEMORY_TRACING
# undef STAMP_AND_REMEMBER_SOURCE
# undef DUMP_BLOCK_MAPS
# undef KEEP_DETAIL_PATH
# define STD_MEMORY_TRACING 1
# define STAMP_AND_REMEMBER_SOURCE 1
# define DUMP_BLOCK_MAPS 1
# define KEEP_DETAIL_PATH 1
#endif

#if STD_MEMORY_TRACING
# undef TERSE_MEMORY_TRACING
# undef DUMP_BLOCK_COUNTS
# define TERSE_MEMORY_TRACING 1
# define DUMP_BLOCK_COUNTS 1
#endif

#if TERSE_MEMORY_TRACING
# undef ALLOW_TRACE_COUNT
# undef ALLOW_TRACE_PATH
# undef ALLOW_SET_FINALIZER
# undef CHECK_WATCH_FOR_PTR_ALLOC
# define ALLOW_TRACE_COUNT 1
# define ALLOW_TRACE_PATH 1
# define ALLOW_SET_FINALIZER 1
# define CHECK_WATCH_FOR_PTR_ALLOC 1
#endif

#if PAD_BOUNDARY_BYTES
# undef CHECK_SIMPLE_INTERIOR_POINTERS
# define CHECK_SIMPLE_INTERIOR_POINTERS 1
#endif

#if DUMP_BLOCK_MAPS
# undef DUMP_BLOCK_COUNTS
# define DUMP_BLOCK_COUNTS 1
#endif

#if PROVIDE_MALLOC_AND_FREE
# if !PROVIDE_GC_FREE
#  define EXTRA_FREE_CHECKS 1
# endif
# undef PROVIDE_GC_FREE
# define PROVIDE_GC_FREE 1
#else
# define EXTRA_FREE_CHECKS 0
#endif

#if PROVIDE_GC_FREE
# undef DISTINGUISH_FREE_FROM_UNMARKED
# define DISTINGUISH_FREE_FROM_UNMARKED 1
#endif

#if ALLOW_TRACE_COUNT || ALLOW_TRACE_PATH || PROVIDE_GC_FREE
# define KEEP_SET_NO 1
#else
# define KEEP_SET_NO 0
#endif

#if PROVIDE_GC_FREE
# define KEEP_PREV_PTR 1
#else
# define KEEP_PREV_PTR 0
#endif

#ifndef NULL
# define NULL 0L
#endif

#if PAD_BOUNDARY_BYTES
# define PAD_START_SIZE (2 * sizeof(long))
# define PAD_END_SIZE sizeof(long)
# define PAD_PATTERN 0x7c7c7c7c
# define PAD_FILL_PATTERN 0xc7
# define SET_PAD(p, s, os) set_pad(p, s, os)
# define PAD_FORWARD(p) ((void *)(((char *)p) + PAD_START_SIZE))
# define PAD_BACKWARD(p) ((void *)(((char *)p) - PAD_START_SIZE))
#else
# define PAD_FORWARD(p) (p)
# define PAD_BACKWARD(p) (p)
#endif


void (*GC_out_of_memory)(void);

/* Sector types: */
enum {
  sector_kind_free,
  sector_kind_freed,
  sector_kind_block,
  sector_kind_chunk,
  sector_kind_managed,
  sector_kind_other
};

typedef struct MemoryBlock {
  struct Finalizer *finalizers;
  unsigned long start;
  unsigned long end;
  unsigned long top;
  short size;
  short atomic;
  short elem_per_block;
#if KEEP_SET_NO
  short set_no;
#endif
  struct MemoryBlock *next;
#if STAMP_AND_REMEMBER_SOURCE
  long make_time;
  long use_time;
  unsigned long low_marker;
  unsigned long high_marker;
#endif
  unsigned char free[1];
} MemoryBlock;

#if DISTINGUISH_FREE_FROM_UNMARKED

# define FREE_BIT_PER_ELEM 4
# define LOG_FREE_BIT_PER_ELEM 2
# define FREE_BIT_SIZE (8 >> LOG_FREE_BIT_PER_ELEM)
# define FREE_BIT_START 0x2 
# define UNMARK_BIT_START 0x1

# define POS_TO_FREE_INDEX(p) (p >> LOG_FREE_BIT_PER_ELEM)
# define POS_TO_UNMARK_INDEX(p) (p >> LOG_FREE_BIT_PER_ELEM)
# define POS_TO_FREE_BIT(p) (FREE_BIT_START << ((p & (FREE_BIT_PER_ELEM - 1)) << 1))
# define POS_TO_UNMARK_BIT(p) (UNMARK_BIT_START << ((p & (FREE_BIT_PER_ELEM - 1)) << 1))

# define ALL_UNMARKED 0x55
# define ALL_FREE 0xAA

# define _NOT_FREE(x) NOT_FREE(x)

# define SHIFT_UNMARK_TO_FREE(x) ((x & ALL_UNMARKED) << 1)
# define SHIFT_COPY_FREE_TO_UNMARKED(x) ((x & ALL_FREE) | ((x & ALL_FREE) >> 1))

#else /* !DISTINGUISH_FREE_FROM_UNMARKED */

# define FREE_BIT_PER_ELEM 8
# define LOG_FREE_BIT_PER_ELEM 3
# define FREE_BIT_SIZE (8 >> LOG_FREE_BIT_PER_ELEM)
# define FREE_BIT_START 0x1
# define UNMARK_BIT_START 0x1

# define POS_TO_FREE_INDEX(p) (p >> LOG_FREE_BIT_PER_ELEM)
# define POS_TO_UNMARK_INDEX(p) (p >> LOG_FREE_BIT_PER_ELEM)
# define POS_TO_FREE_BIT(p) (FREE_BIT_START << (p & (FREE_BIT_PER_ELEM - 1)))
# define POS_TO_UNMARK_BIT(p) (UNMARK_BIT_START << (p & (FREE_BIT_PER_ELEM - 1)))

# define ALL_UNMARKED 0xFF

# define _NOT_FREE(x) 1

#endif /* DISTINGUISH_FREE_FROM_UNMARKED */

#define NOT_FREE(x) (!(x))
#define IS_FREE(x) (x)
#define NOT_MARKED(x) (x)
#define IS_MARKED(x) (!(x))

#define ELEM_PER_BLOCK(b) b->elem_per_block

typedef struct MemoryChunk {
  struct Finalizer *finalizers;
  unsigned long start;
  unsigned long end;
  struct MemoryChunk *next;
#if KEEP_PREV_PTR
  struct MemoryChunk **prev_ptr;
#endif
  short atomic;
  short marked;
#if STAMP_AND_REMEMBER_SOURCE
  long make_time;
  unsigned long marker;
#endif
#if KEEP_SET_NO
  int set_no;
#endif
  char data[1];
} MemoryChunk;

/* If this changes size from 2 ptrs, change LOG_SECTOR_PAGEREC_SIZE */
typedef struct {
  long kind;  /* sector_kind_other, etc. */
  unsigned long start; /* Sector start; may not be accurate if the segment
                          is deallocated, but 0 => not in any sector */
} SectorPage;

static SectorPage **sector_pagetables;

typedef struct SectorFreepage {
  long size; 
  unsigned long start; /* Sector start */
  unsigned long end; /* start of next */
  struct SectorFreepage *next;
  struct SectorFreepage *prev;
} SectorFreepage;

static SectorFreepage *sector_freepage_start, *sector_freepage_end;

#define TABLE_HI_SHIFT LOG_SECTOR_SEGMENT_SIZE
#define TABLE_LO_MASK (SECTOR_SEGMENT_SIZE-1)
#define EACH_TABLE_COUNT (1 << (LOG_SECTOR_SEGMENT_SIZE - LOG_PTR_SIZE))

typedef struct GC_Set {
  short atomic, uncollectable;
#if ALLOW_SET_LOCKING
  short locked;
#endif
  char *name;
  MemoryBlock **blocks;
  MemoryBlock **block_ends;
  MemoryChunk **othersptr;
#if DUMP_BLOCK_COUNTS
  unsigned long total;
#endif
#if ALLOW_TRACE_COUNT
  GC_count_tracer count_tracer;
#endif
#if ALLOW_TRACE_PATH
  GC_path_tracer path_tracer;
#endif
#if ALLOW_TRACE_COUNT || ALLOW_TRACE_PATH
  GC_trace_init trace_init;
  GC_trace_done trace_done;
#endif
#if KEEP_SET_NO
  int no;
#endif
#if ALLOW_SET_FINALIZER
  GC_set_elem_finalizer finalizer;
#endif
} GC_Set;

typedef struct GC_SetWithOthers {
  GC_Set c;
  MemoryChunk *others;
} GC_SetWithOthers;

static GC_Set **common_sets;
static int num_common_sets;

static MemoryBlock *common[NUM_COMMON_SIZE];
static MemoryBlock *common_ends[NUM_COMMON_SIZE];
static MemoryBlock *atomic_common[NUM_COMMON_SIZE];
static MemoryBlock *atomic_common_ends[NUM_COMMON_SIZE];
static MemoryBlock *uncollectable_common[NUM_COMMON_SIZE];
static MemoryBlock *uncollectable_common_ends[NUM_COMMON_SIZE];
static MemoryBlock *uncollectable_atomic_common[NUM_COMMON_SIZE];
static MemoryBlock *uncollectable_atomic_common_ends[NUM_COMMON_SIZE];
static MemoryChunk *others, *atomic_others;
static MemoryChunk *uncollectable_others, *uncollectable_atomic_others;

#if PROVIDE_MALLOC_AND_FREE
static MemoryBlock *sys_malloc[NUM_COMMON_SIZE];
static MemoryBlock *sys_malloc_ends[NUM_COMMON_SIZE];
static MemoryChunk *sys_malloc_others;
#endif

int GC_dl_entries;
int GC_fo_entries;

void (*GC_push_other_roots)(void);

typedef struct DisappearingLink {
  void *watch;
  void **disappear;
  void *saved_value;
  struct DisappearingLink *prev, *next;
} DisappearingLink;

typedef struct Finalizer {
  union {
    void *watch; /* pointer to finalized block; used after queued */
    int pos;     /* position within common block; used before queued */
  } u;
  short eager;
  short ignore_self;
  void *data;
  void (*f)(void *p, void *data);
  struct Finalizer *prev, *next; /* also not needed for chunks */
} Finalizer;

static DisappearingLink *disappearing;
static Finalizer *queued_finalizers, *last_queued_finalizer;

static unsigned long sector_low_plausible, sector_high_plausible;
static unsigned long low_plausible, high_plausible;

void *GC_stackbottom;

static long mem_use, mem_limit = FIRST_GC_LIMIT;

static long mem_real_use, mem_uncollectable_use;

static long sector_mem_use, sector_admin_mem_use, sector_free_mem_use;
static long manage_mem_use, manage_real_mem_use;

static long collect_mem_use;

static long num_sector_allocs, num_sector_frees;

static int collect_off;

#if ALLOW_TRACE_COUNT
static long mem_traced;
#endif

static long num_chunks;
static long num_blocks;

void (*GC_collect_start_callback)(void);
void (*GC_collect_end_callback)(void);
void (*GC_custom_finalize)(void);

static long roots_count;
static long roots_size;
static unsigned long *roots;

#if STAMP_AND_REMEMBER_SOURCE
static long stamp_clock = 0;
#endif

static long *size_index_map; /* (1/PTR_SIZE)th of requested size to alloc index */
static long *size_map; /* alloc index to alloc size */

#if CHECK_COLLECTING
static int collecting_now;
#endif

#if FPRINTF_USE_PRIM_STRINGOUT
static void sgc_fprintf(int, const char *, ...);
# define FPRINTF sgc_fprintf
# define STDERR 0
#else
# define FPRINTF fprintf
# define STDERR stderr
#endif

#if CHECK_FREES
static void free_error(const char *msg)
{
  FPRINTF(STDERR, msg);
}
#endif

/*************************************************************/

/* 
   The kinds of allocation:
   
     malloc_sector = returns new SECTOR_SEGMENT_SIZE-aligned memory;
                     relies on nothing else; the memeory blocks must
		     be explicitly freed with free_sector; all GC
		     allocation is perfomed via sectors
     
     malloc_managed = malloc "atomic" block used by GC implementation
                      itself; no GCing should occur during the malloc;
		      the block is freed with free_managed

     realloc_collect_temp = temporary structures used during gc;
                            no other allocation can take place
			    during gc, and all memory will be freed
                            when GC is done with free_collect_temp
*/

#if GET_MEM_VIA_SBRK
static void *platform_plain_sector(int count)
{
  caddr_t cur_brk = (caddr_t)sbrk(0);
  long lsbs = (unsigned long)cur_brk & TABLE_LO_MASK;
  void *result;
    
  if (lsbs != 0) {
    if ((caddr_t)sbrk(SECTOR_SEGMENT_SIZE - lsbs) == (caddr_t)(-1)) 
      return 0;
  }

  result = (caddr_t)sbrk((count << LOG_SECTOR_SEGMENT_SIZE));

  if (result == (caddr_t)(-1)) 
    return 0;

  return result;
}
#else
# if GET_MEM_VIA_VIRTUAL_ALLOC
static void *platform_plain_sector(int count)
{
  /* Since 64k blocks are used up by each call to VirtualAlloc,
     use roughly the same trick as in the malloc-based alloc to
     avoid wasting ther address space. */

  static int prealloced;
  static void *preallocptr;
  
  if (!prealloced && (count < SECTOR_SEGMENT_GROUP_SIZE)) {
    prealloced = SECTOR_SEGMENT_GROUP_SIZE;
    preallocptr = VirtualAlloc(NULL, prealloced << LOG_SECTOR_SEGMENT_SIZE,
			       MEM_COMMIT | MEM_RESERVE,
			       PAGE_READWRITE);		
  }
  
  if (count <= prealloced) {
    void *result = preallocptr;
    preallocptr = ((char *)preallocptr) + (count << LOG_SECTOR_SEGMENT_SIZE);
    prealloced -= count;
    return result;
  }
  
  return VirtualAlloc(NULL, count << LOG_SECTOR_SEGMENT_SIZE,
		      MEM_COMMIT | MEM_RESERVE,
		      PAGE_READWRITE);
}
# else

#  if PROVIDE_MALLOC_AND_FREE
  >> 
  Error: you must pick a platform-specific allocation mechanism
  to support malloc() and free() 
  <<
#  endif

static void *platform_plain_sector(int count)
{
  static int prealloced;
  static void *preallocptr;

  if (!prealloced) {
    unsigned long d;

    if (count <= (SECTOR_SEGMENT_GROUP_SIZE-1))
      prealloced = SECTOR_SEGMENT_GROUP_SIZE-1;
    else
      prealloced = count;

    preallocptr = MALLOC((prealloced + 1) << LOG_SECTOR_SEGMENT_SIZE);

    d = ((unsigned long)preallocptr) & TABLE_LO_MASK;
    if (d)
      preallocptr = ((char *)preallocptr) + (SECTOR_SEGMENT_SIZE - d);
  }

  if (prealloced >= count) {
    void *r = preallocptr;

    prealloced -= count;
    preallocptr = ((char *)preallocptr) + (count << LOG_SECTOR_SEGMENT_SIZE);
    
    return r;
  }

  {
    unsigned long d;
    void *r;

    r = MALLOC((count + 1) << LOG_SECTOR_SEGMENT_SIZE);

    d = ((unsigned long)r) & TABLE_LO_MASK;
    if (d)
      r = ((char *)r) + (SECTOR_SEGMENT_SIZE - d);

    return r;
  }
}
# endif
#endif

static void *malloc_plain_sector(int count)
{
  void *m;

  m = platform_plain_sector(count);

  if (!m) {
    if (GC_out_of_memory)
      GC_out_of_memory();
    FPRINTF(STDERR, "out of memory\n");	
    exit(-1);
  }

  return m;
}

static void register_sector(void *naya, int need, long kind)
{
  unsigned long ns, orig_ns;
  int pagetableindex, pageindex, i;
  SectorPage *pagetable;

  orig_ns = ns = PTR_TO_INT(naya);
  if (!sector_low_plausible || (ns < sector_low_plausible))
    sector_low_plausible = ns;
  if (!sector_high_plausible 
      || (ns + (need << LOG_SECTOR_SEGMENT_SIZE) > sector_high_plausible))
    sector_high_plausible = ns + (need << LOG_SECTOR_SEGMENT_SIZE);

  /* Register pages as existing: */
  for (i = need; i--; ns += SECTOR_SEGMENT_SIZE) {
    pagetableindex = SECTOR_LOOKUP_PAGETABLE(ns);
    pagetable = sector_pagetables[pagetableindex];
    if (!pagetable) {
      int c = (LOG_SECTOR_LOOKUP_PAGESIZE + LOG_SECTOR_PAGEREC_SIZE) - LOG_SECTOR_SEGMENT_SIZE;
      int j;
      
      if (c < 0)
	c = 0;
      c = 1 << c;
      pagetable = (SectorPage *)malloc_plain_sector(c);
      sector_pagetables[pagetableindex] = pagetable;
      sector_admin_mem_use += (c << LOG_SECTOR_SEGMENT_SIZE);
      for (j = 0; j < SECTOR_LOOKUP_PAGESIZE; j++) {
	pagetable[j].start = 0; 
	pagetable[j].kind = sector_kind_free;
      }
    }

    pageindex = SECTOR_LOOKUP_PAGEPOS(ns);
    pagetable[pageindex].kind = kind;
    pagetable[pageindex].start = orig_ns;
  }
}

static void *malloc_sector(long size, long kind)
{
  long need, i;
  void *naya;
  SectorFreepage *fp;

#if CHECK_COLLECTING
  if (collecting_now) {
    free_error("alloc while collecting\n");
    return NULL;
  }
#endif

  num_sector_allocs++;

  if (!sector_pagetables) {
    int c = (SECTOR_LOOKUP_PAGESETBITS + LOG_PTR_SIZE) - LOG_SECTOR_SEGMENT_SIZE;
    if (c < 0)
      c = 0;
    c = 1 << c;
    sector_pagetables = (SectorPage **)malloc_plain_sector(c);
    sector_admin_mem_use += (c << LOG_SECTOR_SEGMENT_SIZE);
    for (i = 0; i < (1 << SECTOR_LOOKUP_PAGESETBITS); i++)
      sector_pagetables[i] = NULL;
  }

  need = (size + SECTOR_SEGMENT_SIZE - 1) / SECTOR_SEGMENT_SIZE;

  /* This is best-fit when the free-list is sorted by size,
     gravity-fit when the free list is sorted by position. */
  fp = sector_freepage_start;
  while (fp) {
    if (fp->size >= need) {
      naya = INT_TO_PTR(fp->start);
      register_sector(naya, need, kind);
      if (fp->size > need) {
	/* Move freepage info and shrink */
	SectorFreepage *naya;
	unsigned long nfp;
	nfp = fp->start + (need << LOG_SECTOR_SEGMENT_SIZE);
	naya = (SectorFreepage *)INT_TO_PTR(nfp);
	naya->size = fp->size - need;
	naya->start = nfp;
	naya->end = fp->end;
	naya->prev = fp->prev;
	naya->next = fp->next;
	if (fp->prev)
	  fp->prev->next = naya;
	else
	  sector_freepage_start = naya;
	if (fp->next)
	  fp->next->prev = naya;
	else
	  sector_freepage_end = naya;
      } else {
	/* Remove freepage */
	if (fp->prev)
	  fp->prev->next = fp->next;
	else
	  sector_freepage_start = fp->next;
	if (fp->next)
	  fp->next->prev = fp->prev;
	else
	  sector_freepage_end = fp->prev;
      }

      sector_free_mem_use -= (need << LOG_SECTOR_SEGMENT_SIZE);
      return naya;
    } else
      fp = fp->next;
  }

  naya = malloc_plain_sector(need);
  sector_mem_use += (need << LOG_SECTOR_SEGMENT_SIZE);
  register_sector(naya, need, kind);

  return naya;
}

static void free_sector(void *p)
{
  unsigned long s = PTR_TO_INT(p), t;
  int c = 0;
  SectorFreepage *fp, *ifp;

  num_sector_frees++;
  
  /* Determine the size: */
  t = s;
  while(1) {
    long pagetableindex = SECTOR_LOOKUP_PAGETABLE(t);
    long pageindex = SECTOR_LOOKUP_PAGEPOS(t);
    if (sector_pagetables[pagetableindex]
	&& (sector_pagetables[pagetableindex][pageindex].start == s)) {
      sector_pagetables[pagetableindex][pageindex].kind = sector_kind_freed;
      sector_pagetables[pagetableindex][pageindex].start = 0;
      c++;
      t += SECTOR_SEGMENT_SIZE;
    } else
      break;
  }

#if CHECK_FREES
  if (!c) {
    free_error("bad sector free!\n");
    return;
  }
#endif

  sector_free_mem_use += (c << LOG_SECTOR_SEGMENT_SIZE);

  /* Try merge with a predecessor: */
  ifp = sector_freepage_start;
  while (ifp) {
    if (ifp->end == s) {
      /* Remove predecessor freepage */
      if (ifp->prev)
	ifp->prev->next = ifp->next;
      else
	sector_freepage_start = ifp->next;
      if (ifp->next)
	ifp->next->prev = ifp->prev;
      else
	sector_freepage_end = ifp->prev;

      c += ifp->size;
      s = ifp->start;

      break;
    }
    ifp = ifp->next;
  }

  /* Try merge with a successor: */
  ifp = sector_freepage_start;
  while (ifp) {
    if (ifp->start == t) {
      /* Remove successor freepage */
      if (ifp->prev)
	ifp->prev->next = ifp->next;
      else
	sector_freepage_start = ifp->next;
      if (ifp->next)
	ifp->next->prev = ifp->prev;
      else
	sector_freepage_end = ifp->prev;

      c += ifp->size;
      t = ifp->end;

      break;
    }
    ifp = ifp->next;
  }
  
  ifp = sector_freepage_start;
#if USE_BEST_FIT_ON_FREE_SECTORS
  /* Insert after all smaller secots: */
  while (ifp && (ifp->size < c))
    ifp = ifp->next;
#else
  /* Insert after lower sectors: */
  while (ifp && (ifp->start < s))
    ifp = ifp->next;
#endif

  fp = (SectorFreepage *)p;
  fp->start = s;
  fp->end = t;
  fp->size = c;
  if (ifp) {
    fp->prev = ifp->prev;
    if (!ifp->prev)
      sector_freepage_start = fp;
    else
      ifp->prev->next = fp;
    ifp->prev = fp;
    fp->next = ifp;
  } else {
    fp->prev = sector_freepage_end;
    if (sector_freepage_end)
      sector_freepage_end->next = fp;
    fp->next = NULL;
    sector_freepage_end = fp;
    if (!sector_freepage_start)
      sector_freepage_start = fp;
  }
}

#ifdef WIN32
static int is_sector_segment(void *p)
{
  unsigned long s = PTR_TO_INT(p);
  long pagetableindex = SECTOR_LOOKUP_PAGETABLE(s);
  long pageindex = SECTOR_LOOKUP_PAGEPOS(s);

  return (sector_pagetables[pagetableindex]
          && sector_pagetables[pagetableindex][pageindex].start);
}
#endif

#if GET_MEM_VIA_SBRK
static int c_refcount;
static char *save_brk;
#endif

static void prepare_collect_temp()
{
#if GET_MEM_VIA_SBRK
  save_brk = (char *)sbrk(0);
#else
  collect_mem_use = 0;
#endif
}

static void *realloc_collect_temp(void *v, long oldsize, long newsize)
{
#if GET_MEM_VIA_SBRK
  void *naya;

  naya = (void *)sbrk(newsize);
  memcpy(naya, v, oldsize);
  if (!v)
    c_refcount++;
  return naya;
#else
# if GET_MEM_VIA_VIRTUAL_ALLOC
  void *naya;

  naya = VirtualAlloc(NULL, newsize, 
		      MEM_COMMIT | MEM_RESERVE,
		      PAGE_READWRITE);
  memcpy(naya, v, oldsize);
  if (v)
    VirtualFree(v, 0, MEM_RELEASE);

  return naya;
# else
  void *naya;

  naya = MALLOC(newsize);
  memcpy(naya, v, oldsize);
  FREE(v);
  collect_mem_use += newsize;
  return naya;
# endif
#endif
}

static void free_collect_temp(void *v)
{
#if GET_MEM_VIA_SBRK
  if (!(--c_refcount)) {
    collect_mem_use = (unsigned long)(sbrk(0)) - (unsigned long)save_brk;
    brk(save_brk);
  }
#else
# if GET_MEM_VIA_VIRTUAL_ALLOC
  VirtualFree(v, 0, MEM_RELEASE);
# else
  FREE(v);
# endif
#endif
}

typedef struct {
  struct ManagedBlock *next;
  struct ManagedBlock *prev;
  long count;
  long size; /* Use size to find bucket */
  unsigned long end;
} ManagedBlockHeader;

typedef struct ManagedBlock {
  ManagedBlockHeader head;
  char free[1];
} ManagedBlock;

typedef struct {
  long size;
  long perblock;
  long offset;
  ManagedBlock *block;
} ManagedBucket;

typedef struct {
  int num_buckets;
  ManagedBucket buckets[1];
} Managed;

static Managed *managed;

static void *malloc_managed(long size)
{
  /* A naive strategy is sufficient here.
     There will be many disappearing links, many
     finalizations, and very little of anything else. */
  int i, j;
  long perblock, offset;
  ManagedBlock *mb;
  
  if (size & PTR_SIZE)
    size += PTR_SIZE - (size & PTR_SIZE);

  if (!managed) {
    managed = (Managed *)malloc_sector(SECTOR_SEGMENT_SIZE, sector_kind_other);
    managed->num_buckets = 0;
    manage_real_mem_use += SECTOR_SEGMENT_SIZE;
  }

  for (i = 0; i < managed->num_buckets; i++) {
    if (managed->buckets[i].size == size)
      break;
  }

  if (i >= managed->num_buckets) {
    managed->num_buckets++;
    managed->buckets[i].size = size;
    if (size < MAX_COMMON_SIZE) {
      int c;

      mb = (ManagedBlock *)malloc_sector(SECTOR_SEGMENT_SIZE, sector_kind_managed);
      manage_real_mem_use += SECTOR_SEGMENT_SIZE;
      managed->buckets[i].block = mb;

      c = (SECTOR_SEGMENT_SIZE - sizeof(ManagedBlockHeader)) / size;
      if (c & (PTR_SIZE - 1))
	c += (PTR_SIZE - (c & (PTR_SIZE - 1)));
      managed->buckets[i].perblock = (SECTOR_SEGMENT_SIZE - sizeof(ManagedBlockHeader) - c) / size;
      managed->buckets[i].offset = c + sizeof(ManagedBlockHeader);
    } else {
      long l = size + sizeof(ManagedBlockHeader) + PTR_SIZE;
      mb = (ManagedBlock *)malloc_sector(l, sector_kind_managed);
      manage_real_mem_use += l;
      managed->buckets[i].block = mb;
      managed->buckets[i].perblock = 1;
      managed->buckets[i].offset = sizeof(ManagedBlockHeader) + PTR_SIZE;
    }
    mb->head.count = 0;
    mb->head.size = size;
    mb->head.next = NULL;
    mb->head.prev = NULL;
    perblock = managed->buckets[i].perblock;
    for (j = perblock; j--; )
      mb->free[j] = 1;
    mb->head.end = PTR_TO_INT(mb) + managed->buckets[i].offset + size * perblock;
  }

  perblock = managed->buckets[i].perblock;
  offset = managed->buckets[i].offset;
  mb = managed->buckets[i].block;
  while ((mb->head.count == perblock) && mb->head.next)
    mb = mb->head.next;
  if (mb->head.count == perblock) {
    long l = offset + size * perblock;
    mb->head.next = (ManagedBlock *)malloc_sector(l, sector_kind_managed);
    manage_real_mem_use += l;
    mb->head.next->head.prev = mb;
    mb = mb->head.next;
    mb->head.count = 0;
    mb->head.size = size;
    mb->head.next = NULL;
    for (j = perblock; j--; )
      mb->free[j] = 1;
    mb->head.end = PTR_TO_INT(mb) + offset + size * perblock;
  }

  manage_mem_use += size;

  mb->head.count++;
  for (j = perblock; j--; )
    if (mb->free[j]) {
      mb->free[j] = 0;
      return (((char *)mb) + offset) + size * j;
    }

  FPRINTF(STDERR, "error allocating managed\n");
  return NULL;
}

void free_managed(void *s)
{
  int i;
  unsigned long p;
  ManagedBucket *bucket;
  ManagedBlock *mb;

  p = PTR_TO_INT(s);

  /* Assume that s really is an allocated managed pointer: */
  mb = (ManagedBlock *)INT_TO_PTR((p & SECTOR_SEGMENT_MASK));
  
  for (i = 0; i < managed->num_buckets; i++) {
    bucket = managed->buckets + i;
    if (bucket->size == mb->head.size) {
      /* Found bucket */
      int which;
      which = (p - PTR_TO_INT(mb) - bucket->offset) / bucket->size;
      if ((which >= 0) && (which < bucket->perblock)) {
	if (mb->free[which]) {
	  FPRINTF(STDERR, "error freeing managed\n");
	  return;
	}
	mb->free[which] = 1;
	--mb->head.count;
	manage_mem_use -= bucket->size;
	if (!mb->head.count) {
	  if (mb->head.prev) {
	    if (mb->head.next)
	      mb->head.next->head.prev = mb->head.prev;
	    mb->head.prev->head.next = mb->head.next;
	  } else {
	    if (mb->head.next) {
	      bucket->block = mb->head.next;
	      bucket->block->head.prev = NULL;
	    } else {
	      /* Empty bucket */
	      int j;
	      --managed->num_buckets;
	      for (j = i; j < managed->num_buckets; j++)
		memcpy(&(managed->buckets[j]), &(managed->buckets[j + 1]), sizeof(ManagedBucket));
	    }
	  }

	  manage_real_mem_use -= (bucket->offset + bucket->size * bucket->perblock);

	  free_sector(mb);
	}
	return;
      }
    }
  }
  
  FPRINTF(STDERR, "error freeing managed\n");
}

/*************************************************************/

static void init_size_map()
{
  int i, j, find_half;
  long k, next;

  size_index_map = (long *)malloc_sector(MAX_COMMON_SIZE, sector_kind_other);
  size_map = malloc_sector(NUM_COMMON_SIZE * sizeof(long), sector_kind_other);

  i = 0;
  while (i < 8) {
    size_index_map[i] = i;
    size_map[i] = (i + 1) * PTR_SIZE;
    i++;
  }

  k = 8;
  next = 12;
  j = i;
  find_half = 1;
  while (j < (MAX_COMMON_SIZE >> 2)) {
    size_index_map[j] = i;
    if ((j + 1) == next) {
      size_map[i] = next * PTR_SIZE;
      i++;
      if (find_half) {
	next = 2 * k;
      } else {
	next = 3 * k;
	k = 2 * k;
      }
      find_half = !find_half;
    }
    j++;
  }
  if (i < NUM_COMMON_SIZE)
    size_map[i] = next * PTR_SIZE;

#if 0
  FPRINTF(STDERR, "max: %d  num: %d\n", MAX_COMMON_SIZE, NUM_COMMON_SIZE);
  for (i = 0; i < (MAX_COMMON_SIZE >> 2); i++) {
    FPRINTF(STDERR, "%d->%d=%d;", i, 
	    size_index_map[i], 
	    size_map[size_index_map[i]]);
  }
  FPRINTF(STDERR, "\n");
#endif
}

/*************************************************************/

void GC_add_roots(void *start, void *end)
{
  if (roots_count >= roots_size) {
    unsigned long *naya;

    mem_real_use -= (sizeof(unsigned long) * roots_size);

    roots_size = roots_size ? 2 * roots_size : 500;
    naya = (unsigned long *)malloc_managed(sizeof(unsigned long) * (roots_size + 1));

    mem_real_use += (sizeof(unsigned long) * roots_size);

    memcpy((void *)naya, (void *)roots, 
	   sizeof(unsigned long) * roots_count);

    if (roots)
      free_managed(roots);

    roots = naya;
  }

  roots[roots_count++] = PTR_TO_INT(start);
  roots[roots_count++] = PTR_TO_INT(end) - PTR_ALIGNMENT;
}

#if AUTO_STATIC_ROOTS_IF_POSSIBLE

#if defined(_IBMR2)
  extern int end;
# define DATASTART ((void *)0x20000000)
# define DATAEND ((void *)(&end))
# define USE_DATASTARTEND 1
#endif

#if defined(__FreeBSD__) && defined(i386)
  extern char etext;
  extern int end;
# define DATASTART ((void *)(&etext))
# define DATAEND ((void *)(&end))
# define USE_DATASTARTEND 1
#endif

#if defined(linux) && defined(i386) && defined(__ELF__)
# include <linux/version.h>
# include <features.h>
# if LINUX_VERSION_CODE >= 0x20000 && defined(__GLIBC__) && __GLIBC__ >= 2
  extern int __data_start;
#  define DATASTART ((void *)(&__data_start))
# else
   extern int _etext;
#  define DATASTART ((void *)((((word) (&_etext)) + 0xfff) & ~0xfff))
# endif
  extern int _end;
# define DATAEND (&_end)
# define USE_DATASTARTEND 1
#endif

#if defined(sun)
# include <errno.h>
# ifdef ECHRNG
/* Solaris */
  extern char _etext;
  extern int _end;
#  define DATASTART sysv_GetDataStart(0x10000, (int)&_etext)
#  define DATAEND (void *)(&_end)
#  define NEED_SYSV_GET_START
# else
#  define TEXTSTART 0x2000
#  define DATASTART ((ptr_t)(*(int *)(TEXTSTART+0x4)+TEXTSTART))
# endif
# define USE_DATASTARTEND 1
#endif

#ifndef USE_DATASTARTEND
# define USE_DATASTARTEND 0
#endif

#ifdef WIN32
/* Mostly borrowed from conservative GC, Boehm et al. */
static void cond_add_roots(char *base, char * limit, long allocation_granularity)
{
  char dummy;
  char * stack_top;
  
  if (base == limit) return;
  
  stack_top = (char *) ((long)(&dummy) & ~(allocation_granularity-1));
  
  if (limit > stack_top && base < (char *)GC_stackbottom) {
    /* Part of the stack; ignore it. */
    return;
  }
  GC_add_roots(base, limit);
}
  
void register_static_variables()
{
  MEMORY_BASIC_INFORMATION buf;
  SYSTEM_INFO sysinfo;
  DWORD result;
  DWORD protect;
  LPVOID p;
  char * base;
  char * limit, * new_limit;
  long allocation_granularity;
  
  GetSystemInfo(&sysinfo);
  base = limit = p = sysinfo.lpMinimumApplicationAddress;
  allocation_granularity = sysinfo.dwAllocationGranularity;
  while (p < sysinfo.lpMaximumApplicationAddress) {
    result = VirtualQuery(p, &buf, sizeof(buf));
    new_limit = (char *)p + buf.RegionSize;
    protect = buf.Protect;
    if (buf.State == MEM_COMMIT
	&& (protect == PAGE_EXECUTE_READWRITE
	    || protect == PAGE_READWRITE
	    || protect == PAGE_WRITECOPY
	    || protect == PAGE_EXECUTE_WRITECOPY)
	&& !is_sector_segment(buf.AllocationBase)) {
      if ((char *)p == limit) {
	limit = new_limit;
      } else {
	cond_add_roots(base, limit, allocation_granularity);
	base = p;
	limit = new_limit;
      }
    }
    if (p > (LPVOID)new_limit /* overflow */) break;
    p = (LPVOID)new_limit;
  }
  cond_add_roots(base, limit, allocation_granularity);
}

long total_memory_use()
{
  /* Try to count total used bytes in the heap. */
  MEMORY_BASIC_INFORMATION buf;
  SYSTEM_INFO sysinfo;
  LPVOID p;
  char * new_limit;
  long allocation_granularity;
  long total = 0;
    
  GetSystemInfo(&sysinfo);
  p = sysinfo.lpMinimumApplicationAddress;
  allocation_granularity = sysinfo.dwAllocationGranularity;
  while (p < sysinfo.lpMaximumApplicationAddress) {
    VirtualQuery(p, &buf, sizeof(buf));
    new_limit = (char *)p + buf.RegionSize;
    if (buf.State != MEM_FREE)
      total += buf.RegionSize;
    if (p > (LPVOID)new_limit /* overflow */) break;
    p = (LPVOID)new_limit;
  }
  
  return total;
}
#endif /* Win32 */

#ifdef NEED_SYSV_GET_START
/* Also borrowed conservative GC, Boehm et al. */
#include <signal.h>
# define MIN_PAGE_SIZE 256	/* Smallest conceivable page size, bytes */
static jmp_buf sysv_jb;
    
void sysv_fault_handler(int sig)
{
  longjmp(sysv_jb, 1);
}

typedef void (*handler)(int);
# ifdef sun
static struct sigaction oldact;
# else
static handler old_segv_handler, old_bus_handler;
# endif

static void sysv_setup_temporary_fault_handler()
{
# ifdef sun
  struct sigaction act;

  act.sa_handler = sysv_fault_handler;
  act.sa_flags = SA_RESTART | SA_SIGINFO | SA_NODEFER;
  /* The presence of SA_NODEFER represents yet another gross    */
  /* hack.  Under Solaris 2.3, siglongjmp doesn't appear to     */
  /* interact correctly with -lthread.  We hide the confusion   */
  /* by making sure that signal handling doesn't affect the     */
  /* signal mask.                                               */

  (void) sigemptyset(&act.sa_mask);
  (void) sigaction(SIGSEGV, &act, &oldact);
# else
  old_segv_handler = signal(SIGSEGV, sysv_fault_handler);
# ifdef SIGBUS
 old_bus_handler = signal(SIGBUS, sysv_fault_handler);
# endif
# endif
}
    
void sysv_reset_fault_handler()
{
# ifdef sun
  (void) sigaction(SIGSEGV, &oldact, 0);
# else
  (void) signal(SIGSEGV, old_segv_handler);
# ifdef SIGBUS
  (void) signal(SIGBUS, old_bus_handler);
# endif
# endif
}

/* Return the first nonaddressible location > p (up) or 	*/
/* the smallest location q s.t. [q,p] is addressible (!up).	*/
void *sysv_find_limit(void *p, int up)
{
  static void *result;
  static char dummy;
  /* Needs to be static, since otherwise it may not be	*/
  /* preserved across the longjmp.  Can safely be 	*/
  /* static since it's only called once, with the       */
  /* allocation lock held.				*/
  
  sysv_setup_temporary_fault_handler();
  if (setjmp(sysv_jb) == 0) {
    result = (void *)(((unsigned long)(p)) & ~(MIN_PAGE_SIZE-1));
    while(1) {
      if (up)
	result += MIN_PAGE_SIZE;
      else
	result -= MIN_PAGE_SIZE;

      dummy = *(char *)result;
    }
  }
  sysv_reset_fault_handler();
  if (!up)
    result += MIN_PAGE_SIZE;
  return result;
}

void *sysv_GetDataStart(int max_page_size, int etext_addr)
{
  unsigned long text_end = (((unsigned long)(etext_addr) + sizeof(unsigned long) - 1)
			    & ~(sizeof(unsigned long) - 1));
  /* etext rounded to word boundary	*/
  unsigned long next_page = ((text_end + (unsigned long)max_page_size - 1)
			     & ~((unsigned long)max_page_size - 1));
  unsigned long page_offset = (text_end & ((unsigned long)max_page_size - 1));
  char * result = (char *)(next_page + page_offset);
  /* Note that this isnt equivalent to just adding		*/
  /* max_page_size to &etext if &etext is at a page boundary	*/
  
  sysv_setup_temporary_fault_handler();
  if (setjmp(sysv_jb) == 0) {
    /* Try writing to the address.	*/
    *result = *result;
  } else {
    /* We got here via a longjmp.  The address is not readable.	*/
    /* This is known to happen under Solaris 2.4 + gcc, which place	*/
    /* string constants in the text segment, but after etext.	*/
    /* Use plan B.  Note that we now know there is a gap between	*/
    /* text and data segments, so plan A bought us something.	*/
    result = (char *)sysv_find_limit((void *)(DATAEND) - MIN_PAGE_SIZE, 0);
  }
  sysv_reset_fault_handler();
  return (void *)result;
}
#endif /* SysV */

#endif  /* AUTO_STATIC_ROOTS_IF_POSSIBLE */

static int statics_setup = 0;

static void init_static_variables(void)
{
#if AUTO_STATIC_ROOTS_IF_POSSIBLE
# if USE_DATASTARTEND
  GC_add_roots(DATASTART, DATAEND);
# endif
# ifdef WIN32
  register_static_variables();
# endif
#endif

  statics_setup = 1;
}

static int initialized = 0;

void GC_initialize(void)
{
  int i;

#if PROVIDE_MALLOC_AND_FREE
  num_common_sets = 5;
#else
  num_common_sets = 4;
#endif
  common_sets = (GC_Set **)malloc_managed(sizeof(GC_Set*) * num_common_sets);

  common_sets[0] = (GC_Set *)malloc_managed(sizeof(GC_Set));
  common_sets[0]->atomic = 0;
  common_sets[0]->uncollectable = 0;
  common_sets[0]->blocks = common;
  common_sets[0]->block_ends = common_ends;
  common_sets[0]->othersptr = &others;

  common_sets[1] = (GC_Set *)malloc_managed(sizeof(GC_Set));
  common_sets[1]->atomic = 1;
  common_sets[1]->uncollectable = 0;
  common_sets[1]->blocks = atomic_common;
  common_sets[1]->block_ends = atomic_common_ends;
  common_sets[1]->othersptr = &atomic_others;

  common_sets[2] = (GC_Set *)malloc_managed(sizeof(GC_Set));
  common_sets[2]->atomic = 0;
  common_sets[2]->uncollectable = 1;
  common_sets[2]->blocks = uncollectable_common;
  common_sets[2]->block_ends = uncollectable_common_ends;
  common_sets[2]->othersptr = &uncollectable_others;

  common_sets[3] = (GC_Set *)malloc_managed(sizeof(GC_Set));
  common_sets[3]->atomic = 1;
  common_sets[3]->uncollectable = 1;
  common_sets[3]->blocks = uncollectable_atomic_common;
  common_sets[3]->block_ends = uncollectable_atomic_common_ends;
  common_sets[3]->othersptr = &uncollectable_atomic_others;

#if PROVIDE_MALLOC_AND_FREE
  common_sets[4] = (GC_Set *)malloc_managed(sizeof(GC_Set));
  common_sets[4]->atomic = 1;
  common_sets[4]->uncollectable = 1;
  common_sets[4]->blocks = sys_malloc;
  common_sets[4]->block_ends = sys_malloc_ends;
  common_sets[4]->othersptr = &sys_malloc_others;
#endif

  for (i = 0; i < num_common_sets; i++) {
    common_sets[i]->name = "Basic";
#if ALLOW_SET_LOCKING
    common_sets[i]->locked = 0;
#endif
#if KEEP_SET_NO
    common_sets[i]->no = i;
#endif
#if ALLOW_TRACE_COUNT
    common_sets[i]->count_tracer = NULL;
#endif
#if ALLOW_TRACE_PATH
    common_sets[i]->path_tracer = NULL;
#endif
#if ALLOW_TRACE_COUNT || ALLOW_TRACE_PATH
    common_sets[i]->trace_init = NULL;
    common_sets[i]->trace_done = NULL;
#endif
#if ALLOW_SET_FINALIZER
    common_sets[i]->finalizer = NULL;
#endif    
  }

#if PROVIDE_MALLOC_AND_FREE
  common_sets[4]->name = "Sysmalloc";
#endif

  initialized = 1;
}

void GC_set_stack_base(void *base)
{
  GC_stackbottom = base;
}

void *GC_get_stack_base(void)
{
  return GC_stackbottom;
}

void *find_ptr(void *d, int *_size,
	       MemoryBlock **_block, int *_pos,
	       MemoryChunk **_chunk,
	       int find_anyway)
{
  unsigned long p = PTR_TO_INT(d);

  if (!sector_pagetables)
    return NULL;

  if (p >= low_plausible && p < high_plausible) {
    SectorPage *pagetable = sector_pagetables[SECTOR_LOOKUP_PAGETABLE(p)];
    if (pagetable) {
      SectorPage *page = pagetable + SECTOR_LOOKUP_PAGEPOS(p);
      long kind = page->kind;

      if (kind == sector_kind_block) {
	/* Found common block: */
	MemoryBlock *block = (MemoryBlock *)INT_TO_PTR(page->start);
	if (p >= block->start && p < block->top) {
	  int size = block->size;
	  int diff = p - block->start;
	  int pos = (diff / size), apos;
	  int bit;
	  unsigned long result;
	  
	  apos = POS_TO_UNMARK_INDEX(pos);
	  bit = POS_TO_UNMARK_BIT(pos);
	  
	  if (_size)
	    *_size = size;
	  
	  if (NOT_MARKED(block->free[apos] & bit) && !find_anyway)
	    return NULL;
	  
	  result = block->start + (pos * size);
	  
	  if (_block)
	    *_block = block;
	  if (_pos)
	    *_pos = pos;
	  
	  return INT_TO_PTR(result);
	}
      } else if (kind == sector_kind_chunk) {
	MemoryChunk *c = (MemoryChunk *)INT_TO_PTR(page->start);
	if ((p >= c->start) && (p < c->end)) {
	  if (_size)
	    *_size = (c->end - c->start);
	  if (c->marked || find_anyway) {
	    if (_chunk)
	      *_chunk = c;
	    return INT_TO_PTR(c->start);
	  } else
	    return NULL;
	}
      }
    }
  }

  return NULL;
}

void *GC_base(void *d)
{
  void *p;

  p = find_ptr(d, NULL, NULL, NULL, NULL, 0);

#if PAD_BOUNDARY_BYTES
  if (p)
    p = PAD_FORWARD(p);
#endif
  
  return p;
}

int GC_size(void *d)
{
  int size;
  
  if (find_ptr(d, &size, NULL, NULL, NULL, 0)) {
#if PAD_BOUNDARY_BYTES
    size -= PAD_START_SIZE + PAD_END_SIZE;
#endif
    return size;
  } else
    return 0;
}

int GC_is_atomic(void *d)
{
  MemoryBlock *block = NULL;
  MemoryChunk *chunk = NULL;
  
  if (find_ptr(d, NULL, &block, NULL, &chunk, 0)) {
    if (block)
      return block->atomic;
    else
      return chunk->atomic;
  } else
    return 0;
}

int GC_orig_size(void *d)
{
  int size = 0;
  
  find_ptr(d, &size, NULL, NULL, NULL, 0);
  return size;
}

void *GC_orig_base(void *d)
{
  return find_ptr(d, NULL, NULL, NULL, NULL, 1);
}

struct GC_Set *GC_set(void *d)
{
#if KEEP_SET_NO
  MemoryBlock *block = NULL;
  MemoryChunk *chunk = NULL;
  
  if (!initialized)
    GC_initialize();

  if (find_ptr(d, NULL, &block, NULL, &chunk, 0)) {
    int set_no;
    if (block)
      set_no = block->set_no;
    else
      set_no = chunk->set_no;

    return common_sets[set_no];
  } else
    return NULL;
#else
  return NULL;
#endif
}

#if DUMP_BLOCK_MAPS
static unsigned long trace_stack_start, trace_stack_end, trace_reg_start, trace_reg_end;
#endif

#if DUMP_SECTOR_MAP
static void dump_sector_map(char *prefix)
{
  FPRINTF(STDERR, "%sBegin Sectors\n"
	  "%sO0:free; ,.:block; =-:chunk; mn:other; \"':other; %d each\n%s",
	  prefix, prefix, SECTOR_SEGMENT_SIZE, prefix);
  {
    int i, j;
    int c = 0;
    unsigned long was_sec = 0;
    int was_kind = 0;

    for (i = 0; i < (1 << SECTOR_LOOKUP_PAGESETBITS); i++) {
      SectorPage *pagetable;
      pagetable = sector_pagetables[i];
      if (pagetable) {
	for (j = 0; j < SECTOR_LOOKUP_PAGESIZE; j++) {
	  long kind;
	  kind = pagetable[j].kind;
	  if (kind) {
	    char *same_sec, *diff_sec;

	    if (c++ > 40) {
	      FPRINTF(STDERR, "\n%s", prefix);
	      c = 1;
	    }

	    switch(kind) {
	    case sector_kind_freed:
	      same_sec = "0";
	      diff_sec = "O";
	      break;
	    case sector_kind_block:
	      same_sec = ".";
	      diff_sec = ",";
	      break;
	    case sector_kind_chunk:
	      same_sec = "-";
	      diff_sec = "=";
	      break;
	    case sector_kind_managed:
	      same_sec = "n";
	      diff_sec = "m";
	      break;
	    case sector_kind_other:
	      same_sec = "'";
	      diff_sec = "\"";
	      break;
	    default:
	      same_sec = "?";
	      diff_sec = "?";
	      break;
	    }

	    if ((was_kind != kind) || (was_sec != pagetable[j].start))
	      same_sec = diff_sec;

	    FPRINTF(STDERR, same_sec);
	    
	    was_kind = kind;
	    was_sec = pagetable[j].start;
	  }
	}
      }
    }
  }
  FPRINTF(STDERR, "\n%sEnd Sectors\n", prefix);
}
#endif

void GC_dump(void)
{
  FPRINTF(STDERR, "Begin Map\n");

  FPRINTF(STDERR,
	  "allocated: %ld  collectable: %ld  uncollectable: %ld\n"
	  "including known overhead: %ld  scheduled gc: %ld  last collect depth: %ld\n"
	  "managed: %ld  managed including overhead: %ld\n"
	  "sector used: %ld  sector free: %ld  sector total: %ld\n"
	  "sector range: %ld  sector administration: %ld\n"
	  "num sector allocs: %ld  num sector frees: %ld\n"
#if STAMP_AND_REMEMBER_SOURCE
	  "current clock: %ld\n"
#endif
	  , mem_use + mem_uncollectable_use, mem_use, mem_uncollectable_use, 
	  mem_real_use, mem_limit, collect_mem_use,
	  manage_mem_use, manage_real_mem_use,
	  sector_mem_use - sector_free_mem_use, sector_free_mem_use, sector_mem_use,
	  sector_high_plausible - sector_low_plausible,
	  sector_admin_mem_use,
	  num_sector_allocs, num_sector_frees
#if STAMP_AND_REMEMBER_SOURCE
	  , stamp_clock
#endif
	  );

#if DUMP_SECTOR_MAP
  dump_sector_map("");
#endif

#if DUMP_BLOCK_COUNTS
  {
    int i, j;
    unsigned long total;
    
#if DUMP_BLOCK_MAPS
    FPRINTF(STDERR, "roots: ======================================\n");
    for (i = 0; i < roots_count; i += 2)
      FPRINTF(STDERR, ">%lx-%lx", roots[i], roots[i + 1]);
    FPRINTF(STDERR, "\n");

    FPRINTF(STDERR, "stack: ======================================\n");
    FPRINTF(STDERR, ">%lx-%lx>%lx-%lx\n",
	    trace_stack_start, trace_stack_end, trace_reg_start, trace_reg_end);
#endif

    for (j = 0; j < num_common_sets; j++) {
      GC_Set *cs = common_sets[j];

      total = 0;

      FPRINTF(STDERR,
	      "Set: %s [%s/%s]: ======================================\n", 
	      cs->name,
	      cs->atomic ? "atomic" : "pointerful",
	      cs->uncollectable ? "eternal" : "collectable");

      for (i = 0; i < NUM_COMMON_SIZE; i++) {
	MemoryBlock *block;
	int counter = 0;

	block = (cs)->blocks[i];

	if (block) {
	  FPRINTF(STDERR, "%d:", block->size);

#if DUMP_BLOCK_MAPS
	  FPRINTF(STDERR, "[%lx]", block->start - (unsigned long)block);
#endif

	  while (block) {
	    int k, size = block->size;

#if DUMP_BLOCK_MAPS
	    counter = 0;
#endif

	    for (k = (block->top - block->start) / block->size; k-- ; ) {
	      int bit = POS_TO_UNMARK_BIT(k);
	      int pos = POS_TO_UNMARK_INDEX(k);
	      
	      if (IS_MARKED(block->free[pos] & bit)) {
		total += size;
		counter++;
	      }
	    }

#if DUMP_BLOCK_MAPS
	    FPRINTF(STDERR,
		    ">%lxx%d"
#if STAMP_AND_REMEMBER_SOURCE
		    "@%ld-%ld:%lx-%lx" 
#endif
		    , (unsigned long)block, counter
#if STAMP_AND_REMEMBER_SOURCE
		    , block->make_time, 
		    block->use_time,
		    block->low_marker,
		    block->high_marker
#endif
		    );
#endif
	    block = block->next;
	  }
#if DUMP_BLOCK_MAPS
	  FPRINTF(STDERR, "\n");
#else
	  FPRINTF(STDERR, "%d;", counter);
#endif
	}
      }

      /* Print chunks, "sorting" so that same size are printed together: */
      {
	MemoryChunk *c, *cnext, *first = NULL, *last = NULL, *t, *next, *prev;
	int counter = 0;
	
	for (c = *(cs->othersptr); c; c = cnext) {
	  unsigned long size = c->end - c->start;
	  FPRINTF(STDERR, "%ld:", size);

#if DUMP_BLOCK_MAPS
	  FPRINTF(STDERR, "[%lx]", c->start - (unsigned long)c);
#endif
	  
	  cnext = c->next;
	  
	  prev = NULL;
	  for (t = c; t; t = next) {
	    next = t->next;
	    
	    if (size == (t->end - t->start)) {
#if DUMP_BLOCK_MAPS
	      FPRINTF(STDERR,
		      ">%lx"
#if STAMP_AND_REMEMBER_SOURCE
		      "@%ld:%lx" 
#endif
		      , (unsigned long)t
#if STAMP_AND_REMEMBER_SOURCE
		      , t->make_time,
		      t->marker
#endif
		      );
#endif
	      
	      counter++;

	      if (last)
		last->next = t;
	      else
		first = t;
	      last = t;
	      if (prev)
		prev->next = t->next;
	      if (t == cnext)
		cnext = t->next;

	      total += size;
	    } else
	      prev = t;
	  }
#if DUMP_BLOCK_MAPS
	  FPRINTF(STDERR, "\n");
#else
	  FPRINTF(STDERR, "%d;", counter);
	  counter = 0;
#endif
	}
	
	if (last)
	  last->next = NULL;
	*(cs->othersptr) = first;
      }
      cs->total = total;

#if KEEP_PREV_PTR
      /* reset prev pointers: */
      {
	MemoryChunk *c, **prev_ptr = (cs->othersptr);
	for (c = *(cs->othersptr); c; c = c->next) {
	  c->prev_ptr = prev_ptr;
	  prev_ptr = &c->next;
	}
      }
#endif
      
      FPRINTF(STDERR, "total size: %ld\n", total);
    }

    FPRINTF(STDERR, "summary: ======================================\n");
    total = 0;
    for (j = 0; j < num_common_sets; j++) {
      GC_Set *cs = common_sets[j];
      FPRINTF(STDERR,
	      "%12s: %10ld  [%s/%s]\n",
	      cs->name, cs->total,
	      cs->atomic ? "atomic" : "pointerful",
	      cs->uncollectable ? "eternal" : "collectable");
      total += cs->total;
    }
    FPRINTF(STDERR, "%12s: %10ld\n", "total", total);
  }
#endif
  FPRINTF(STDERR, "End Map\n");
}

void GC_end_stubborn_change(void *p)
{
  /* stubborness is not exploited */
}

static void *zero_ptr;

#if CHECK_WATCH_FOR_PTR_ALLOC
void *GC_watch_for_ptr = NULL;
#define UNHIDE_WATCH(p) ((void *)~((unsigned long)p))
static int findings;

#if USE_WATCH_FOUND_FUNC
void GC_found_watch()
{
  FPRINTF(STDERR, "found\n");
  findings++;
}
#endif
#endif

#if PAD_BOUNDARY_BYTES
static void set_pad(void *p, long s, long os)
{
  long diff;

  /* Set start & end pad: */
  *(long*)p = PAD_PATTERN;
  *(long*)(((char *)p) + s - PAD_END_SIZE) = PAD_PATTERN;
  
  /* Keep giev - requested diff: */
  diff = (s - os - PAD_START_SIZE - PAD_END_SIZE);
  ((long *)p)[1] = diff;
  
  if (diff) {
    unsigned char *ps = ((unsigned char *)p) + os + PAD_START_SIZE;
    while (diff--)
      *(ps++) = PAD_FILL_PATTERN;
  }
}
#endif

#if KEEP_SET_NO
#define SET_NO_BACKINFO int set_no,
#define KEEP_SET_INFO_ARG(x) x, 
#else
#define SET_NO_BACKINFO /* empty */
#define KEEP_SET_INFO_ARG(x) /* empty */
#endif

void *do_malloc(SET_NO_BACKINFO
		unsigned long size, 
		MemoryBlock **common, MemoryBlock **common_ends,
		MemoryChunk **othersptr,
		int atomic, int uncollectable)
{
  MemoryBlock **find, *block;
  void *s;
  long c;
  unsigned long p;
  long sizeElemBit;
  int i, cpos, elem_per_block;
#if PAD_BOUNDARY_BYTES
  long origsize;
#endif

#if CHECK_COLLECTING
  if (collecting_now) {
    exit(-1);
  }
#endif

  if (!size)
    return (void *)&zero_ptr;

  if (!size_map)
    init_size_map();

#if PAD_BOUNDARY_BYTES
  origsize = size;
  size += PAD_START_SIZE + PAD_END_SIZE;
#endif

  /* Round up to ptr-aligned size: */
  if (size & (PTR_SIZE-1))
    size += PTR_SIZE - (size & (PTR_SIZE-1));

  if (size < MAX_COMMON_SIZE) {
    cpos = size_index_map[(size >> LOG_PTR_SIZE) - 1];
#if 0
    if (size > size_map[cpos]) {
      FPRINTF(STDERR, "map error: %d < %d\n", size_map[cpos], size);
    }
#endif
    size = size_map[cpos];

    block = common_ends[cpos];
    find = NULL;

    while (block) {
      if (block->top < block->end)
	goto block_top;

      for (i = block->elem_per_block; i-- ; )
	if (block->free[i]) {
	  char *zp;
	  int v = block->free[i], n;
	  
	  c = i * FREE_BIT_PER_ELEM;
	  n = (FREE_BIT_START | UNMARK_BIT_START);
	  while (IS_MARKED(v & n)) {
	    n = n << FREE_BIT_SIZE;
	    c++;
	  }
	  block->free[i] -= n;
	  
	  if (uncollectable)
	    mem_uncollectable_use += size;
	  else
	    mem_use += size;
	  
	  p = block->start + c * size;

	  zp = INT_TO_PTR(p);

	  if (!atomic) {
	    void **p = (void **)zp;
	    unsigned long sz = size >> LOG_PTR_SIZE;
	    for (; sz--; p++)
	      *p = 0;
	  }

#if CHECK_WATCH_FOR_PTR_ALLOC
	  if (zp == UNHIDE_WATCH(GC_watch_for_ptr)) {
#if USE_WATCH_FOUND_FUNC
	    GC_found_watch();
#else
	    findings++;
#endif
	  }
#endif

#if PAD_BOUNDARY_BYTES
	  SET_PAD(zp, size, origsize);
	  zp = PAD_FORWARD(zp);
#endif

	  return zp;
	}
      
      find = &block->next;

      block = block->next;
      common_ends[cpos] = block;
    }

  } else {
    void *a;
    MemoryChunk *c;

    cpos = 0;

    if (!collect_off && (mem_use >= mem_limit))
      GC_gcollect();

    a = malloc_sector(size + sizeof(MemoryChunk), sector_kind_chunk);

    c = (MemoryChunk *)a;
    
    c->finalizers = NULL;
    c->marked = 1;

#if STAMP_AND_REMEMBER_SOURCE
    c->make_time = stamp_clock;
#endif
#if KEEP_SET_NO
    c->set_no = set_no;
#endif

    c->next = *othersptr;
#if CHECK_FREES
    if (PTR_TO_INT(c->next) & (SECTOR_SEGMENT_SIZE - 1))
      free_error("bad next\n");
#endif
    *othersptr = c;
#if KEEP_PREV_PTR
    c->prev_ptr = othersptr;
    if (c->next)
      c->next->prev_ptr = &c->next;
#endif
    
    c->start = PTR_TO_INT(&c->data);
    c->end = c->start + size;
    c->atomic = atomic;

    if (uncollectable)
      mem_uncollectable_use += size;
    else
      mem_use += size;
    mem_real_use += (size + sizeof(MemoryChunk));
    num_chunks++;

    if (!low_plausible || (c->start < low_plausible))
      low_plausible = c->start;
    if (!high_plausible || (c->end > high_plausible))
      high_plausible = c->end;	

    if (!atomic) {
      void **p = (void **)&c->data;
      unsigned long sz = size >> LOG_PTR_SIZE;
      for (; sz--; p++)
	*p = 0;
    }

#if CHECK_WATCH_FOR_PTR_ALLOC
    if ((&c->data) == UNHIDE_WATCH(GC_watch_for_ptr)) {
#if USE_WATCH_FOUND_FUNC
      GC_found_watch();
#else
      findings++;
#endif
    }
#endif

    s = (void *)&c->data;

#if PAD_BOUNDARY_BYTES
    SET_PAD(s, size, origsize);
    s = PAD_FORWARD(s);
#endif

    return s;
  }

  if (!collect_off && (mem_use >= mem_limit)) {
    GC_gcollect();
    return do_malloc(KEEP_SET_INFO_ARG(set_no)
		     size, common, common_ends, othersptr, 
		     atomic, uncollectable);
  }

  sizeElemBit = size << LOG_FREE_BIT_PER_ELEM;

  /* upper bound: */
  elem_per_block = (SECTOR_SEGMENT_SIZE - sizeof(MemoryBlock) - (PTR_SIZE - 2)) / sizeElemBit;
  /* use this one: */
  elem_per_block = (SECTOR_SEGMENT_SIZE - sizeof(MemoryBlock) - (PTR_SIZE - 2) - elem_per_block) / sizeElemBit;
  if (elem_per_block) {
    /* Small enough to fit into one segment */
    block = (MemoryBlock *)malloc_sector(SECTOR_SEGMENT_SIZE, sector_kind_block);
  } else {
    long alloc_size;
    elem_per_block = 1;
    /* Add (PTR_SIZE - 1) to ensure engouh room after alignment: */
    alloc_size = sizeof(MemoryBlock) + (PTR_SIZE - 1) + sizeElemBit;
    block = (MemoryBlock *)malloc_sector(alloc_size, sector_kind_block);
  }
  
  block->elem_per_block = elem_per_block;

  block->finalizers = NULL;

#if STAMP_AND_REMEMBER_SOURCE
  block->make_time = stamp_clock;
#endif
#if KEEP_SET_NO
  block->set_no = set_no;
#endif

  /* offset for data (4-byte aligned): */
  c = sizeof(MemoryBlock) + (elem_per_block - 1);
  if (c & 0x3)
    c += (4 - (c & 0x3));
  p = PTR_TO_INT(block) + c;

  if (common_ends[cpos] || (find && !common[cpos])) {
    /* hey! - GC happened and reset stuff. find may not be alive anymore,
       so find it again. */
    find = &common_ends[cpos];
    while (*find)
      find = &(*find)->next;
  }

  if (find)
    *find = block;
  else if (!common[cpos])
    common[cpos] = block;

  if (!common_ends[cpos])
    common_ends[cpos] = block;

  num_blocks++;

  for (i = ELEM_PER_BLOCK(block); i-- ; )
    block->free[i] = 0;

  block->start = block->top = p;
  block->end = block->start + (elem_per_block * sizeElemBit);
  block->size = (short)size;
  block->next = NULL;
  block->atomic = atomic;

  if (!low_plausible || (block->start < low_plausible))
    low_plausible = block->start;
  if (!high_plausible || (block->end > high_plausible))
    high_plausible = block->end;	

  mem_real_use += SECTOR_SEGMENT_SIZE;

 block_top:

#if STAMP_AND_REMEMBER_SOURCE
  block->use_time = stamp_clock;
#endif

#if CHECK
  if (block->end < block->start
      || block->top < block->start
      || block->top > block->end)
    FPRINTF(STDERR,
	    "bad block: %ld %ld %ld %ld\n",
	    size, block->start, block->top, block->end);
#endif      

  s = INT_TO_PTR(block->top);
  block->top = block->top + size;

  if (uncollectable)
    mem_uncollectable_use += size;
  else
    mem_use += size;

  if (!atomic) {
    void **p = (void **)s;
    unsigned long sz = size >> LOG_PTR_SIZE;
    for (; sz--; p++)
      *p = 0;
  }

#if CHECK_WATCH_FOR_PTR_ALLOC
  if (s == UNHIDE_WATCH(GC_watch_for_ptr)) {
#if USE_WATCH_FOUND_FUNC
    GC_found_watch();
#else
    findings++;
#endif
  }
#endif

#if PAD_BOUNDARY_BYTES
    SET_PAD(s, size, origsize);
    s = PAD_FORWARD(s);
#endif

  return s;
}

struct GC_Set *GC_new_set(char *name, 
			  GC_trace_init trace_init,
			  GC_trace_done trace_done,
			  GC_count_tracer count_tracer,
			  GC_path_tracer path_tracer,
			  GC_set_elem_finalizer final,
			  int flags)
{
  GC_Set *c, **naya;
  int i;

  if (!initialized)
    GC_initialize();

  c = (GC_Set *)malloc_managed(sizeof(GC_SetWithOthers));

  naya = (GC_Set **)malloc_managed(sizeof(GC_Set *) * (num_common_sets + 1));
  for (i = 0; i < num_common_sets; i++)
    naya[i] = common_sets[i];
  
#if KEEP_SET_NO
  c->no = num_common_sets;
#endif
#if ALLOW_TRACE_COUNT
  c->count_tracer = count_tracer;
#endif
#if ALLOW_TRACE_PATH
  c->path_tracer = path_tracer;
#endif
#if ALLOW_TRACE_COUNT || ALLOW_TRACE_PATH
  c->trace_init = trace_init;
  c->trace_done = trace_done;
#endif
#if ALLOW_SET_FINALIZER
  c->finalizer = final;
#endif    

  naya[num_common_sets++] = c;
  c->atomic = !!(flags & SGC_ATOMIC_SET);
  c->uncollectable = !!(flags & SGC_UNCOLLECTABLE_SET);
#if ALLOW_SET_LOCKING
  c->locked = 0;
#endif
  c->name = name;
  c->blocks = (MemoryBlock **)malloc_managed(sizeof(MemoryBlock*) * NUM_COMMON_SIZE);
  memset(c->blocks, 0, sizeof(MemoryBlock*) * NUM_COMMON_SIZE);
  c->block_ends = (MemoryBlock **)malloc_managed(sizeof(MemoryBlock*) * NUM_COMMON_SIZE);
  memset(c->block_ends, 0, sizeof(MemoryBlock*) * NUM_COMMON_SIZE);

  ((GC_SetWithOthers *)c)->others = NULL;
  c->othersptr = &((GC_SetWithOthers *)c)->others;

  free_managed(common_sets);
  common_sets = naya;

  return c;
}

void *GC_malloc(size_t size)
{
  return do_malloc(KEEP_SET_INFO_ARG(0)
		   size, common, common_ends, &others, 0, 0);
}

void *GC_malloc_atomic(size_t size)
{
  return do_malloc(KEEP_SET_INFO_ARG(1)
		   size, atomic_common, atomic_common_ends, 
		   &atomic_others, !NO_ATOMIC, 0);
}

void *GC_malloc_uncollectable(size_t size)
{
  return do_malloc(KEEP_SET_INFO_ARG(2)
		   size, uncollectable_common, uncollectable_common_ends, 
		   &uncollectable_others, 0, 1);
}

void *GC_malloc_atomic_uncollectable(size_t size)
{
  return do_malloc(KEEP_SET_INFO_ARG(3)
		   size, uncollectable_atomic_common, uncollectable_atomic_common_ends, 
		   &uncollectable_atomic_others, !NO_ATOMIC, 1);
}

void *GC_malloc_specific(size_t size, struct GC_Set *set)
{
  return do_malloc(KEEP_SET_INFO_ARG(set->no)
		   size, set->blocks, set->block_ends, set->othersptr, 
		   set->atomic, set->uncollectable);
}

void *GC_malloc_stubborn(size_t size)
{
  return GC_malloc(size);
}

#if PROVIDE_MALLOC_AND_FREE
void *malloc(size_t size)
{
  return do_malloc(KEEP_SET_INFO_ARG(4)
		   size, sys_malloc, sys_malloc_ends, 
		   &sys_malloc_others, 1, 1);
}

void *realloc(void *p, size_t size)
{
  void *naya;
  size_t oldsize;

  if (p) {
    oldsize = (size_t)GC_size(p);
    if (!oldsize)
      FPRINTF(STDERR, "illegal realloc\n");
  } else
    oldsize = 0;
  naya = malloc(size);
  if (oldsize > size)
    oldsize = size;
  memcpy(naya, p, oldsize);
  if (p)
    free(p);
  return naya;
}

void *calloc(size_t n, size_t size)
{
  void *p;
  long c;

  c = n * size;
  p = malloc(c);
  memset(p, 0, c);

  return p;
}

void free(void *p)
{
  if (p)
    GC_free(p);
}

#ifdef WIN32
size_t _msize(void *p)
{
	return GC_size(p);
}
#endif

#endif

void GC_general_register_disappearing_link(void **p, void *a)
{
  DisappearingLink *dl;
    
  dl = (DisappearingLink *)malloc_managed(sizeof(DisappearingLink));
  dl->watch = a;
  dl->disappear = p;
  dl->saved_value = NULL;
  dl->prev = NULL;
  dl->next = disappearing;
  if (dl->next)
    dl->next->prev = dl;
  disappearing = dl;

  GC_dl_entries++;

  mem_real_use += sizeof(DisappearingLink);
}

DisappearingLink *GC_find_dl(void *p)
{
  DisappearingLink *dl;

  for (dl = disappearing; dl; dl = dl->next)
    if ((dl->watch == p) || (!dl->watch && (*dl->disappear == p)))
      return dl;

  return NULL;
}

static void register_finalizer(void *p, void (*f)(void *p, void *data), 
			       void *data, void (**oldf)(void *p, void *data), 
			       void **olddata, int eager, int ignore_self)
{
  MemoryBlock *block = NULL;
  MemoryChunk *chunk = NULL;
  int pos;

  if ((p = find_ptr(p, NULL, &block, &pos, &chunk, 0))) {
    Finalizer *fn;

    if (block) {
      fn = block->finalizers;
      while (fn && (fn->u.pos != pos))
	fn = fn->next;
      if (fn && !f) {
	if (fn->prev)
	  fn->prev->next = fn->next;
	else
	  block->finalizers = fn->next;
	if (fn->next)
	  fn->next->prev = fn->prev;
      }
    } else {
      fn = chunk->finalizers;
      if (fn && !f)
	chunk->finalizers = NULL;
    }

    if (oldf)
      *oldf = (fn ? fn->f : NULL);
    if (olddata)
      *olddata = (fn ? fn->data : NULL);
    
    if (f) {
      int isnaya = !fn;

      if (!fn) {
	fn = (Finalizer *)malloc_managed(sizeof(Finalizer));
	mem_real_use += sizeof(Finalizer);
	GC_fo_entries++;
      }

      fn->u.pos = pos;
      fn->f = f;
      fn->data = data;
      fn->eager = eager;
      fn->ignore_self = ignore_self;
      
      if (isnaya) {
	fn->prev = NULL;
	if (block) {
	  fn->next = block->finalizers;
	  if (fn->next)
	    fn->next->prev = fn;
	  block->finalizers = fn;
	} else {
	  chunk->finalizers = fn;
	  fn->next = NULL;
	}
      }
    } else if (fn) {
      mem_real_use -= sizeof(Finalizer);
      free_managed(fn);
      --GC_fo_entries;
    }
  }
}

void GC_register_finalizer(void *p, void (*f)(void *p, void *data), 
			   void *data, void (**oldf)(void *p, void *data), 
			   void **olddata)
{
  register_finalizer(PAD_BACKWARD(p), f, data, oldf, olddata, 0, 0);
}

void GC_register_eager_finalizer(void *p, void (*f)(void *p, void *data), 
				 void *data, void (**oldf)(void *p, void *data), 
				 void **olddata)
{
  register_finalizer(PAD_BACKWARD(p), f, data, oldf, olddata, 1, 0);
}

void GC_register_finalizer_ignore_self(void *p, void (*f)(void *p, void *data), 
				       void *data, void (**oldf)(void *p, void *data), 
				       void **olddata)
{
  register_finalizer(PAD_BACKWARD(p), f, data, oldf, olddata, 0, 1);
}

/******************************************************************/

void GC_for_each_element(struct GC_Set *set,
			 void (*f)(void *p, int size, void *data),
			 void *data)
{
  int i;
  MemoryBlock **blocks = set->blocks;
  MemoryChunk *c = *(set->othersptr);

#if ALLOW_SET_LOCKING
  if (!set->uncollectable)
    set->locked++;
#endif

  for (i = 0; i < NUM_COMMON_SIZE; i++) {
    MemoryBlock **prev = &blocks[i];
    MemoryBlock *block = *prev;

    while (block) {
      int j;

      j = (block->top - block->start) / block->size;
      
      while (j--) {
	int bit = POS_TO_FREE_BIT(j);
	int pos = POS_TO_FREE_INDEX(j);
	
	if (IS_MARKED(block->free[pos] & bit)) {
	  unsigned long p;
	  void *s;
	  
	  p = block->start + (block->size * j);
	  s = INT_TO_PTR(p);
	  
#if PAD_BOUNDARY_BYTES
	  s = PAD_FORWARD(s);
#endif
	  
	  f(s, block->size, data);
	}
      }
      block = block->next;
    }
  }

  for (; c; c = c->next) {
    void *s;

    s = INT_TO_PTR(c->start);

#if PAD_BOUNDARY_BYTES
    s = PAD_FORWARD(s);
#endif

    f(s, c->end - c->start, data);
  }

#if ALLOW_SET_LOCKING
  if (!set->uncollectable)
    --set->locked;
#endif
}

/******************************************************************/

static void free_chunk(MemoryChunk *k, MemoryChunk **prev, struct GC_Set *set)
{
  MemoryChunk *next;
  
#if ALLOW_SET_FINALIZER
  if (set->finalizer) {
    void *s = INT_TO_PTR(k->start);
#if PAD_BOUNDARY_BYTES
    s = PAD_FORWARD(s);
#endif
    set->finalizer(s);
  }
#endif
  
  mem_real_use -= (k->end - k->start + sizeof(MemoryChunk));
  
#if PRINT && 0
  FPRINTF(STDERR, "free chunk: %ld (%ld) %d %d\n", 
	  (unsigned long)k, k->end - k->start,
	  set->atomic, set->uncollectable);
#endif
  
  next = k->next;

#if KEEP_PREV_PTR
  if (next)
    next->prev_ptr = k->prev_ptr;
#endif

#if CHECK_FREES
  if (PTR_TO_INT(next) & (SECTOR_SEGMENT_SIZE - 1))
    free_error("bad next\n");
#endif

  *prev = next;

  free_sector(k);
  --num_chunks;
}

#if PROVIDE_GC_FREE
void GC_free(void *p) 
{
  MemoryBlock *block = NULL;
  MemoryChunk *chunk = NULL;
  int fpos;
  void *found;
  struct GC_Set *set;

#if CHECK_COLLECTING && CHECK_FREES
  if (collecting_now)
    free_error("GC_free during collection\n");
#endif

  found = find_ptr(p, NULL, &block, &fpos, &chunk, 1);
  if (!found) {
#if CHECK_FREES
    char b[256];
    sprintf(b, "GC_free failed! %lx\n", (long)p);
    free_error(b);
#endif
    return;
  }

  if (PAD_FORWARD(found) == p) {
    if (block) {
      int i;
      int pos = POS_TO_FREE_INDEX(fpos);
      int fbit = POS_TO_FREE_BIT(fpos);
      int ubit = POS_TO_UNMARK_BIT(fpos);

#if CHECK_FREES
      if (block->free[pos] & fbit) {
	char b[256];
	sprintf(b, "Block element already free! %lx\n", (long)p);
	return;
      }
# if EXTRA_FREE_CHECKS
      if (block->set_no != 4) {
	char b[256];
	sprintf(b, "GC_free on ptr from wrong block! %lx\n", (long)p);
	free_error(b);
	return;
      }
# endif
#endif

      block->free[pos] |= (fbit | ubit);

	  if (!initialized)
		GC_initialize();

      set = common_sets[block->set_no];
      
#if ALLOW_SET_FINALIZER
      if (set->finalizer)
	set->finalizer(p);
#endif

      {
	int size;
#if PAD_BOUNDARY_BYTES
	size = block->size - PAD_START_SIZE - PAD_END_SIZE;
	((long *)found)[1] = 0; /* 0 extra */
#else
	size = block->size;
#endif

	/* Clear, since collection scans whole block. */
	memset(p, 0, size);
      }

      /* Make sure this block is reachable from block_ends: */
      i = size_index_map[(block->size >> LOG_PTR_SIZE) - 1];
      if (set->block_ends[i] != block)
	set->block_ends[i] = set->blocks[i];

      if (set->uncollectable)
	mem_uncollectable_use -= block->size;
    } else {
#if CHECK_FREES && EXTRA_FREE_CHECKS
      if (chunk->set_no != 4) {
	char b[256];
	sprintf(b, "GC_free on ptr from wrong block! %lx\n", (long)p);
	free_error(b);
	return;
      }
#endif
      set = common_sets[chunk->set_no];
      if (set->uncollectable)
	mem_uncollectable_use -= (chunk->end - chunk->start);
      free_chunk(chunk, chunk->prev_ptr, set);
    }
  }
#if CHECK_FREES
  else {
    char b[256];
    sprintf(b, "GC_free on block interior! %lx != %lx\n", 
	    (long)p, (long)PAD_FORWARD(found));
    free_error(b);
  }
#endif

}
#endif

/******************************************************************/

#if CHECK
static long cmn_count, chk_count;
#endif

#if ALLOW_TRACE_COUNT
static int collecting_with_trace_count;

#define TRACE_COLLECT_SWITCH !collecting_with_trace_count
#else
#define TRACE_COLLECT_SWITCH 1
#endif

#if ALLOW_TRACE_PATH
static int collecting_with_trace_path;
static char *current_trace_source;

/* Buffer used to store paths, since allocation is not allowed: */
# define TRACE_PATH_BUFFER_SIZE 1048576
static void *trace_path_buffer[TRACE_PATH_BUFFER_SIZE];
static int trace_path_buffer_pos;
#endif

#if PAD_BOUNDARY_BYTES
static void bad_pad(char *where, void *s, long sz, long diff, long offset, 
		    long pd, long expect)
{
  FPRINTF(STDERR,
	  "pad %s violation at %lx, len %ld (diff %ld+%ld): %lx != %lx\n", 
	  where, (unsigned long)s, sz, diff, offset, pd, expect);
}
#endif

static void collect_init_chunk(MemoryChunk *c, int uncollectable)
{
  for (; c; c = c->next) {
    if (uncollectable && TRACE_COLLECT_SWITCH)
      c->marked = 1;
    else
      c->marked = 0;

#if PAD_BOUNDARY_BYTES
    /* Test padding: */
    {
      void *s = INT_TO_PTR(c->start);
      long pd, sz, diff;
      sz = c->end - c->start;
      diff = ((long *)s)[1];
      pd = *(long *)s;
      if (pd != PAD_PATTERN)
	bad_pad("start", s, sz, diff, 0, pd, PAD_PATTERN);
      pd = *(long *)INT_TO_PTR(c->end - PAD_END_SIZE);
      if (pd != PAD_PATTERN)
	bad_pad("end", s, sz, diff, 0, pd, PAD_PATTERN);
      if (diff) {
	/* Given was bigger than requested; check extra bytes: */
	unsigned char *ps = ((unsigned char *)s) + sz - PAD_END_SIZE - diff;
	long d = 0;
	while (d < diff) {
	  if (*ps != PAD_FILL_PATTERN) {
	    bad_pad("extra", s, sz, diff, d, *ps, PAD_FILL_PATTERN);
	  }
	  ps++;
	  d++;
	}
      }
    }
#endif

#if CHECK
    chk_count++;
    if ((!low_plausible || (c->start < low_plausible))
	|| (!high_plausible || (c->end > high_plausible)))
      FPRINTF(STDERR, "implausible chunk!\n");
#endif
  }
}

static void collect_finish_chunk(MemoryChunk **c, struct GC_Set *set)
{
  while (*c) {
    MemoryChunk *k = *c;

    if (k->marked) {
      c = &k->next;

      if (!low_plausible || (k->start < low_plausible))
	low_plausible = k->start;
      if (!high_plausible || (k->end > high_plausible))
	high_plausible = k->end;	
    } else
      free_chunk(k, c, set);
  }
}

static void collect_init_common(MemoryBlock **blocks, int uncollectable)
{
  int i, j;
  int boundary, boundary_val = 0;

  for (i = 0; i < NUM_COMMON_SIZE; i++) {
    MemoryBlock *block = blocks[i];
    long size = size_map[i];

    while (block) {
#if CHECK
      cmn_count++;
      if ((!low_plausible || (block->start < low_plausible))
	  || (!high_plausible || (block->end > high_plausible)))
	FPRINTF(STDERR, "implausible block!\n");
#endif

#if STAMP_AND_REMEMBER_SOURCE
      block->low_marker = block->high_marker = 0;
#endif

#if PAD_BOUNDARY_BYTES
      /* Test padding: */
      {
	unsigned long p;
	
	for (p = block->start; p < block->top; p += size) {
	  void *s = INT_TO_PTR(p);
	  long pd, diff;
	  pd = *(long *)s;
	  diff = ((long *)s)[1];
	  if (pd != PAD_PATTERN)
	    bad_pad("start", s, size, diff, 0, pd, PAD_PATTERN);
	  pd = *(long *)INT_TO_PTR(p + size - PAD_END_SIZE);
	  if (pd != PAD_PATTERN)
	    bad_pad("end", s, size, diff, 0, pd, PAD_PATTERN);
	  if (diff) {
	    /* Given was bigger than requested; check extra bytes: */
	    unsigned char *ps = ((unsigned char *)s) + size - PAD_END_SIZE - diff;
	    long d = 0;
	    while (d < diff) {
	      if (*ps != PAD_FILL_PATTERN) {
		bad_pad("extra", s, size, diff, d, *ps, PAD_FILL_PATTERN);
	      }
	      ps++;
	      d++;
	    }
	  }
	}
      }
#endif

      if (uncollectable && TRACE_COLLECT_SWITCH) {
	for (j = ELEM_PER_BLOCK(block); j-- ; ) {
#if DISTINGUISH_FREE_FROM_UNMARKED
	  block->free[j] = SHIFT_COPY_FREE_TO_UNMARKED(block->free[j]);
#else
	  block->free[j] = 0;
#endif
	}
      } else {
	if (block->top < block->end) {
	  unsigned long diff = block->top - block->start;
	  diff /= size;
	  boundary = POS_TO_UNMARK_INDEX(diff);
	  boundary_val = (POS_TO_UNMARK_BIT(diff) - 1) & ALL_UNMARKED;
	} else
	  boundary = ELEM_PER_BLOCK(block);

	for (j = ELEM_PER_BLOCK(block); j-- ; ) {
	  if (j < boundary)
	    block->free[j] |= ALL_UNMARKED;
	  else if (j == boundary)
	    block->free[j] = boundary_val;
	  else
	    block->free[j] = 0;
	}
      }

      block = block->next;
    }
  }
}

static void collect_finish_common(MemoryBlock **blocks, 
				  MemoryBlock **block_ends, 
				  struct GC_Set *set)
{
  int i;

  for (i = 0; i < NUM_COMMON_SIZE; i++) {
    MemoryBlock **prev = &blocks[i];
    MemoryBlock *block = *prev;
#if CHECK
    long size = size_map[i];
#endif

    while (block) {
      int allfree;
#if CHECK
      if (block->end < block->start
	  || block->top < block->start
	  || block->top > block->end)
	FPRINTF(STDERR,
		"bad block: %ld %ld %ld %ld\n",
		size, block->start, block->top, block->end);
#endif
#if NO_FREE_BLOCKS
      block->allfree = 0;
#endif

#if ALLOW_SET_FINALIZER
      if (set->finalizer) {
	unsigned long s;
	int j;
	for (j = 0, s = block->start; s < block->top; s += block->size, j++) {
	  int pos = POS_TO_UNMARK_INDEX(j);
	  int bit = POS_TO_UNMARK_BIT(j);

	  if (NOT_MARKED(block->free[pos] & bit)) {
	    void *p = INT_TO_PTR(s);
#if PAD_BOUNDARY_BYTES
	    p = PAD_FORWARD(p);
#endif
	    set->finalizer(p);
	  }
	}
      }
#endif

      allfree = 1;
      {
	int j;
	for (j = ELEM_PER_BLOCK(block); j-- ; )
	  if ((block->free[j] & ALL_UNMARKED) != ALL_UNMARKED) {
	    allfree = 0;
	    break;
	  }
      }

      if (allfree) {
	--num_blocks;
	
	*prev = block->next;
	free_sector(block);
	mem_real_use -= SECTOR_SEGMENT_SIZE;

	block = *prev;
      } else {
#if DISTINGUISH_FREE_FROM_UNMARKED
	/* If it's unmarked, free it: */
	int j;

	for (j = ELEM_PER_BLOCK(block); j-- ; )
	  block->free[j] |= SHIFT_UNMARK_TO_FREE(block->free[j]);
#endif

	if (!low_plausible || (block->start < low_plausible))
	  low_plausible = block->start;
	if (!high_plausible || (block->end > high_plausible))
	  high_plausible = block->end;

	prev = &block->next;
	block = block->next;
      }
    }

    block_ends[i] = blocks[i];
  }
}

static int collect_stack_count;
static int collect_stack_size;
static unsigned long *collect_stack;

static int collect_end_stackbased;

#if KEEP_DETAIL_PATH
# define PUSH_SRC(src) collect_stack[collect_stack_count++] = src;
# define COLLECT_STACK_FRAME_SIZE 3
#else
# define PUSH_SRC(src) /*empty*/
# define COLLECT_STACK_FRAME_SIZE 2
#endif

static void push_collect(unsigned long start, unsigned long end, unsigned long src)
{
  if (collect_stack_count >= collect_stack_size) {
    long oldsize;

    if (collect_stack)
      oldsize = sizeof(unsigned long) * (collect_stack_size + (COLLECT_STACK_FRAME_SIZE - 1));
    else
      oldsize = 0;

    collect_stack_size = collect_stack_size ? 2 * collect_stack_size : 500;
    collect_stack = (unsigned long *)realloc_collect_temp(collect_stack, 
							  oldsize, 
							  sizeof(unsigned long) 
							  * (collect_stack_size + (COLLECT_STACK_FRAME_SIZE - 1)));
  }

  collect_stack[collect_stack_count++] = start;
  collect_stack[collect_stack_count++] = end;
  PUSH_SRC(src)
}

#define PUSH_COLLECT(s, e, src) \
  if (collect_stack_count < collect_stack_size) { \
    collect_stack[collect_stack_count++] = s; \
    collect_stack[collect_stack_count++] = e + 1 - PTR_ALIGNMENT; \
    PUSH_SRC(src) \
  } else \
    push_collect(s, e + 1 - PTR_ALIGNMENT, src);

#if ALLOW_TRACE_COUNT

typedef struct {
  int count, size;
  unsigned long *stack;
} TraceStack;

static void init_trace_stack(TraceStack *s)
{
  s->size = s->count = 0;
  s->stack = NULL;
}

static void done_trace_stack(TraceStack *s)
{
  if (s->stack)
    free_collect_temp(s->stack);
}

static void push_trace_stack(unsigned long v, TraceStack *s)
{
  if (s->count >= s->size) {
    long oldsize;

    if (s->stack)
      oldsize = sizeof(unsigned long)*(s->size + 1);
    else
      oldsize = 0;

    s->size = s->size ? 2 * s->size : 500;
    s->stack = (unsigned long *)realloc_collect_temp(s->stack,
						     oldsize,
						     sizeof(unsigned long)*(s->size + 1));
  }

  s->stack[s->count++] = v;
}

#define PUSH_TS(v, s) \
  if (s.count < s.size) { \
    s.stack[s.count++] = (unsigned long)(v); \
  } else \
    push_trace_stack((unsigned long)(v), &s);

#define POP_TS(s) (s.stack[--s.count])

#endif

#if ALLOW_TRACE_COUNT

TraceStack collect_trace_stack, collect_wait_trace_stack;

static int collect_start_tracing;
static int collect_end_tracing;
static int collect_trace_count;

#define PUSH_TRACE(v) PUSH_TS(v, collect_trace_stack)
#define PUSH_WAIT_TRACE(v) PUSH_TS(v, collect_wait_trace_stack)

#define POP_TRACE() POP_TS(collect_trace_stack)
#define POP_WAIT_TRACE() POP_TS(collect_wait_trace_stack)

#endif

#if ALLOW_TRACE_PATH

TraceStack collect_trace_path_stack;

static int collect_end_path_elem;

#define PUSH_PATH_ELEM(v) PUSH_TS(v, collect_trace_path_stack)

#define POP_PATH_ELEM() POP_TS(collect_trace_path_stack)

#define PATH_ELEM_STACK_NONEMPTY() (collect_trace_path_stack.count)

#endif

static void collect()
{
  int stack_cycle = 0;
  int offset = 0; /* for interior */
  
  while (collect_stack_count) {
    unsigned long s, end;
#if KEEP_DETAIL_PATH
    unsigned long source;
#endif
    int interior;

#if ALLOW_TRACE_COUNT
    if (collect_stack_count == collect_start_tracing) {
      void *tracing_for_object;
      GC_count_tracer count_tracer;
      int size;

      tracing_for_object = (void *)POP_WAIT_TRACE();
      count_tracer = (GC_count_tracer)POP_WAIT_TRACE();
      size = POP_WAIT_TRACE();

      /* Push current trace onto the stack: */
      PUSH_TRACE(collect_end_tracing);
      PUSH_TRACE(collect_trace_count);
      PUSH_TRACE(count_tracer);
      PUSH_TRACE(tracing_for_object);

      collect_trace_count = size;
  
      collect_end_tracing = collect_start_tracing - COLLECT_STACK_FRAME_SIZE;

      collect_start_tracing = POP_WAIT_TRACE();
    }
#endif

    if (collect_stack_count == collect_end_stackbased) {
      interior = 1;

#if KEEP_DETAIL_PATH
      source = collect_stack[collect_stack_count - (COLLECT_STACK_FRAME_SIZE - 2)];
#endif
      end = collect_stack[collect_stack_count - (COLLECT_STACK_FRAME_SIZE - 1)];
      s = collect_stack[collect_stack_count - COLLECT_STACK_FRAME_SIZE];

#if PRINT && 0
      FPRINTF(STDERR, "stack at %ld: [%lx,%lx]\n", collect_end_stackbased, s, end);
#endif

      /* do everything twice, backing up one pointer alignment 
	 to catch references just past the end of an array. */
      if (stack_cycle || NO_STACK_OFFBYONE) {
	collect_stack_count -= COLLECT_STACK_FRAME_SIZE;
	collect_end_stackbased -= COLLECT_STACK_FRAME_SIZE;
#if NO_STACK_OFFBYONE
	offset = 0;
#else
	offset = -PTR_ALIGNMENT;
#endif
	stack_cycle = 0;
      } else {
	offset = 0;
	stack_cycle = 1;
      }
    } else {
      interior = CHECK_SIMPLE_INTERIOR_POINTERS;
      offset = 0;
#if KEEP_DETAIL_PATH
      source = collect_stack[--collect_stack_count];
#endif
      end = collect_stack[--collect_stack_count];
      s = collect_stack[--collect_stack_count];
    }

#if ALLOW_TRACE_PATH
    if (collecting_with_trace_path) {
      PUSH_PATH_ELEM(collect_end_path_elem);
      PUSH_PATH_ELEM(s);
# if KEEP_DETAIL_PATH
      PUSH_PATH_ELEM(source);
# else
      PUSH_PATH_ELEM(0);
# endif
      collect_end_path_elem = collect_stack_count;
    }
#endif

    for (; s < end; s += PTR_ALIGNMENT) {
      void *d = *(void **)INT_TO_PTR(s);
      unsigned long p = PTR_TO_INT(d) + offset;

      if (p >= low_plausible && p < high_plausible) {
	SectorPage *pagetable = sector_pagetables[SECTOR_LOOKUP_PAGETABLE(p)];
	if (pagetable) {
	  SectorPage *page = pagetable + SECTOR_LOOKUP_PAGEPOS(p);
	  long kind = page->kind;
	  
	  if (kind == sector_kind_block) {
	    /* Found common block: */
	    MemoryBlock *block = (MemoryBlock *)INT_TO_PTR(page->start);
	    int size = block->size;
	    int diff = p - block->start;
	    int pos = (diff / size);
	    
	    if ((diff >= 0) && (p < block->top) 
		&& ((diff == pos * size) || interior)) {
	      int bpos;
	      int bit;
#if DISTINGUISH_FREE_FROM_UNMARKED
	      int fbit;
#endif
	      
	      bpos = POS_TO_UNMARK_INDEX(pos);
	      bit = POS_TO_UNMARK_BIT(pos);
#if DISTINGUISH_FREE_FROM_UNMARKED
	      fbit = POS_TO_FREE_BIT(pos);
#endif
	      
	      if (NOT_MARKED(block->free[bpos] & bit)
		  && _NOT_FREE(block->free[bpos] & fbit)) {
#if ALLOW_TRACE_COUNT
		if (collecting_with_trace_count) {
		  GC_count_tracer count_tracer;
		  if ((count_tracer = common_sets[block->set_no]->count_tracer)) {
		    void *o;
		    if (interior)
		      p = block->start + (pos * size);
		    o = INT_TO_PTR(p);
		    if (block->atomic) {
		      void *s = o;
#if PAD_BOUNDARY_BYTES
		      s = PAD_FORWARD(s);
#endif
		      count_tracer(s, size); 
		      mem_traced += size;
		    } else {
		      /* Push new trace onto the stack: */
		      PUSH_WAIT_TRACE(collect_start_tracing);
		      PUSH_WAIT_TRACE(size);
		      PUSH_WAIT_TRACE(count_tracer);
		      PUSH_WAIT_TRACE(o);
		      collect_start_tracing = collect_stack_count + COLLECT_STACK_FRAME_SIZE;
		    }
		  } else
		    collect_trace_count += size;
		}
#endif
#if ALLOW_TRACE_PATH
		if (collecting_with_trace_path) {
		  GC_path_tracer path_tracer;
		  if ((path_tracer = common_sets[block->set_no]->path_tracer)) {
		    void *o;
		    if (interior)
		      p = block->start + (pos * size);
		    o = INT_TO_PTR(p);
#if PAD_BOUNDARY_BYTES
		    o = PAD_FORWARD(o);
#endif
		    path_tracer(o, s, &collect_trace_path_stack);
		  }
		}
#endif
		
#if PRINT && 0
		if (interior && (diff % size))
		  FPRINTF(STDERR,
			  "inexact block: %d for %lx[%d], %d=(%d, %d) {%d} %lx -> %lx\n", 
			  diff % size, block, size, pos, bpos, bit,
			  block->free[bpos], p, block->start + (pos * size));
#endif
		
		block->free[bpos] -= bit;
		
		mem_use += size;
		
		if (!block->atomic) {
		  if (interior)
		    p = block->start + (pos * size);
		  PUSH_COLLECT(p, p + size, s);
		}
		
#if STAMP_AND_REMEMBER_SOURCE
		if (!block->low_marker || (s < block->low_marker))
		  block->low_marker = s;
		if (!block->high_marker || (s > block->high_marker))
		  block->high_marker = s;
#endif
	      }
	    }
	  } else if (kind == sector_kind_chunk) {
	    MemoryChunk *c = (MemoryChunk *)INT_TO_PTR(page->start);
	    
	    if (((p == c->start) 
		 || (interior && (p > c->start) && (p < c->end)))
		&& !c->marked) {
#if ALLOW_TRACE_COUNT
	      if (collecting_with_trace_count) {
		GC_count_tracer count_tracer;
		int size = (c->end - c->start);
		if ((count_tracer = common_sets[c->set_no]->count_tracer)) {
		  void *o;
		  o = INT_TO_PTR(c->start);
		  if (c->atomic) {
		    void *s = o;
#if PAD_BOUNDARY_BYTES
		    s = PAD_FORWARD(s);
#endif
		    count_tracer(s, size); 
		    mem_traced += size;
		  } else {
		    /* Push new trace onto the stack: */
		    PUSH_WAIT_TRACE(collect_start_tracing);
		    PUSH_WAIT_TRACE(size);
		    PUSH_WAIT_TRACE(count_tracer);
		    PUSH_WAIT_TRACE(o);
		    collect_start_tracing = collect_stack_count + COLLECT_STACK_FRAME_SIZE;
		  }
		} else
		  collect_trace_count += size;
	      }
#endif
#if ALLOW_TRACE_PATH
	      if (collecting_with_trace_path) {
		GC_path_tracer path_tracer;
		if ((path_tracer = common_sets[c->set_no]->path_tracer)) {
		  void *o;
		  o = INT_TO_PTR(c->start);
#if PAD_BOUNDARY_BYTES
		  o = PAD_FORWARD(o);
#endif
		  path_tracer(o, s, &collect_trace_path_stack);
		}
	      }
#endif

#if PRINT && 0
	      if (interior && (p != c->start))
		FPRINTF(STDERR, "inexact chunk: %lx != %lx\n", p, c->start);
#endif
#if PRINT && 0
	      FPRINTF(STDERR,
		      "push %ld (%ld) from %ld\n",
		      p, (c->end - c->start), s);
#endif
	      c->marked = 1;
	      mem_use += (c->end - c->start);
	      if (!c->atomic) {
		PUSH_COLLECT(c->start, c->end, s);
	      }
#if STAMP_AND_REMEMBER_SOURCE
	      c->marker = s;
#endif
	    }
	  }
	}
      }
    }

#if ALLOW_TRACE_COUNT
    while (collect_stack_count == collect_end_tracing) {
      void *tracing_for_object, *s;
      GC_count_tracer count_tracer;
      
      tracing_for_object = (void *)POP_TRACE();
      count_tracer = (GC_count_tracer)POP_TRACE();

      s = tracing_for_object;
#if PAD_BOUNDARY_BYTES
      s = PAD_FORWARD(s);
#endif
      count_tracer(s, collect_trace_count);
      mem_traced += collect_trace_count;

      collect_trace_count = POP_TRACE();
      collect_end_tracing = POP_TRACE();
    }
#endif
#if ALLOW_TRACE_PATH
    if (collecting_with_trace_path) {
      while (PATH_ELEM_STACK_NONEMPTY() && (collect_stack_count == collect_end_path_elem)) {
	(void)POP_PATH_ELEM(); /* source */
	(void)POP_PATH_ELEM(); /* obj */
	collect_end_path_elem = POP_PATH_ELEM();
      }
    }
#endif
  }

#if ALLOW_TRACE_COUNT && CHECK
  if (collect_trace_stack.count)
    FPRINTF(STDERR, "BOO-BOO: trace stack not emty: %d\n", collect_trace_stack.count);
  if (collect_wait_trace_stack.count)
    FPRINTF(STDERR, "BOO-BOO: wait trace stack not emty: %d\n", collect_wait_trace_stack.count);
#endif
}

static jmp_buf buf;

/* Sparc fix borrowed from SCM, so here's the copyright:  */
/* Scheme implementation intended for JACAL.
   Copyright (C) 1990, 1991, 1992, 1993, 1994 Aubrey Jaffer. */
/* James Clark came up with this neat one instruction fix for
   continuations on the SPARC.  It flushes the register windows so
   that all the state of the process is contained in the stack. */
#ifdef sparc
#define FLUSH_REGISTER_WINDOWS asm("ta 3")
#else
#define FLUSH_REGISTER_WINDOWS /* empty */
#endif

static void push_stack(void *stack_now)
{
  unsigned long start, end;

  start = PTR_TO_INT(GC_stackbottom);
  end = PTR_TO_INT(stack_now);

#if PRINT && STAMP_AND_REMEMBER_SOURCE
  FPRINTF(STDERR, "stack in [%lx, %lx]\n", start, end);
#endif

  if (start < end) {
    PUSH_COLLECT(start, end, 0);
  } else {
    PUSH_COLLECT(end, start, 0);
  }

#if DUMP_BLOCK_MAPS
  trace_stack_start = collect_stack[collect_stack_count - COLLECT_STACK_FRAME_SIZE];
  trace_stack_end = collect_stack[collect_stack_count - (COLLECT_STACK_FRAME_SIZE - 1)];
#endif

  start = PTR_TO_INT((void *)&buf);
  end = start + sizeof(buf);
  PUSH_COLLECT(start, end, 0);

#if DUMP_BLOCK_MAPS
  trace_reg_start = collect_stack[collect_stack_count - COLLECT_STACK_FRAME_SIZE];
  trace_reg_end = collect_stack[collect_stack_count - (COLLECT_STACK_FRAME_SIZE - 1)];
#endif

#if PRINT && STAMP_AND_REMEMBER_SOURCE
  FPRINTF(STDERR, "jmpbuf in [%lx, %lx]\n", start, end);
#endif
}

#if ALLOW_SET_LOCKING
static void push_locked_chunk(MemoryChunk *c, int atomic)
{
  for (; c; c = c->next) {
    unsigned long size = (c->end - c->start);
    mem_use += size;
    collect_trace_count += size;
    if (!atomic) {
      PUSH_COLLECT(c->start, c->end, 0);
    }
  }
}

static void push_locked_common(MemoryBlock **blocks, int atomic)
{
  int i;

  for (i = 0; i < NUM_COMMON_SIZE; i++) {
    MemoryBlock *block = blocks[i];
    
    for (; block; block = block->next) {
      unsigned long size = block->size;
      unsigned long start = block->start;
      unsigned long top = block->top;
      int j;
      
      for (j = 0; start < top; start += size, j++) {
	int bit = POS_TO_UNMARK_BIT(j);
	int pos = POS_TO_UNMARK_INDEX(j);
	if (IS_MARKED(block->free[pos] & bit)) {
	  if (!atomic) {
	    PUSH_COLLECT(start, start + size, 0);
	  }
	  mem_use += size;
	  collect_trace_count += size;
	}
      }
    }
  }
}

#endif

static void push_uncollectable_chunk(MemoryChunk *c, struct GC_Set *set)
{
#if ALLOW_TRACE_COUNT
  if (!collecting_with_trace_count
      || !c
      || !set->count_tracer) {
#endif
    for (; c; c = c->next) {
#if ALLOW_TRACE_COUNT
      if (!c->marked) {
	if (collecting_with_trace_count) {
	  c->marked = 1;
	  collect_trace_count += (c->end - c->start);
	}
	if (!set->atomic) {
#endif      
	  PUSH_COLLECT(c->start, c->end, 0);
#if ALLOW_TRACE_COUNT
	}
      } else {
	/* It got marked the normal way; deduct the size. */
	mem_use -= (c->end - c->start);
      }
#endif
    }
#if ALLOW_TRACE_COUNT
  } else {
    int save_count = collect_trace_count;
    for (; c; c = c->next) {
      if (!c->marked) {
	void *s;
	c->marked = 1;
	collect_trace_count = 0;
	if (!c->atomic) {
	  PUSH_COLLECT(c->start, c->end, 0);
	  collect();
	}
	collect_trace_count += (c->end - c->start);

	s = INT_TO_PTR(c->start);
#if PAD_BOUNDARY_BYTES
	s = PAD_FORWARD(s);
#endif
	set->count_tracer(s, collect_trace_count);
	mem_traced += collect_trace_count;
      } else {
	/* It got marked the normal way; deduct the size. */
	mem_use -= (c->end - c->start);
      }
    }
    collect_trace_count = save_count;
  }
#endif
}

static void push_uncollectable_common(MemoryBlock **blocks, struct GC_Set *set)
{
  int i;

#if ALLOW_TRACE_COUNT
  if (!collecting_with_trace_count) {
#endif
    for (i = 0; i < NUM_COMMON_SIZE; i++) {
      MemoryBlock *block = blocks[i];
      
      while (block) {
	PUSH_COLLECT(block->start, block->top, 0);
	block = block->next;
      }
    }
#if ALLOW_TRACE_COUNT
  } else {
    int save_count = collect_trace_count;

    for (i = 0; i < NUM_COMMON_SIZE; i++) {
      MemoryBlock *block = blocks[i];
      
      while (block) {
	unsigned long size = block->size;
	unsigned long start = block->start;
	unsigned long top = block->top;
	int j;
	
	for (j = 0; start < top; start += size, j++) {
	  int bit;
	  int pos;
	  int fbit;

	  pos = POS_TO_UNMARK_INDEX(j);
	  bit = POS_TO_UNMARK_BIT(j);
	  fbit = POS_TO_FREE_BIT(j);

	  if (NOT_MARKED(block->free[pos] & bit)
	      && _NOT_FREE(block->free[pos] & fbit)) {
	    block->free[pos] -= bit;
	    if (set->count_tracer)
	      collect_trace_count = 0;
	    else
	      collect_trace_count += size;
	    if (!block->atomic) {
	      PUSH_COLLECT(start, start + size, 0);
	      collect();
	    }
	    if (set->count_tracer) {
	      void *s;
	      collect_trace_count += size;
	      s = INT_TO_PTR(start);
#if PAD_BOUNDARY_BYTES
	      s = PAD_FORWARD(s);
#endif
	      set->count_tracer(s, collect_trace_count);
	      mem_traced += collect_trace_count;
	    }
	  } else {
	    /* It got marked the normal way; deduct the size. */
	    mem_use -= size;
	  }
	}

	block = block->next;
      }
    }

    if (set->count_tracer)
      collect_trace_count = save_count;
  }
#endif
}


static void push_collect_ignore(unsigned long s, unsigned long e, 
				unsigned long a)
/* Like PUSH_COLLECT, but immediate references to `a' are avoided */
{
  unsigned long push_from = s;

#if PAD_BOUNDARY_BYTES
  a = PTR_TO_INT(PAD_FORWARD(INT_TO_PTR(a)));
#endif

  for (; s < e; s += PTR_ALIGNMENT) {
    void *d = *(void **)INT_TO_PTR(s);
    unsigned long p = PTR_TO_INT(d);

    if (p == a) {
      if (push_from != s) {
	PUSH_COLLECT(push_from, s, a);
      }
      push_from = s + PTR_ALIGNMENT;
    }
  }

  if (push_from != s) {
    PUSH_COLLECT(push_from, s, a);
  }
}

static void mark_chunks_for_finalizations(MemoryChunk *c)
{
  for (; c; c = c->next) {
    Finalizer *fn = c->finalizers;

    if (fn) {
      /* Always mark data associated with finalization: */
      unsigned long p = PTR_TO_INT(&fn->data);
      PUSH_COLLECT(p, p + PTR_SIZE, 0);

      /* If not eager, mark data reachable from finalized block: */
      if (!fn->eager && !c->marked && !c->atomic) {
	if (fn->ignore_self)
	  push_collect_ignore(c->start, c->end, c->start);
	else {
	  PUSH_COLLECT(c->start, c->end, 0);
	}
      }
    }
  }

  collect();
}

static void mark_common_for_finalizations(MemoryBlock **blocks, int atomic)
{
  int i;

  for (i = 0; i < NUM_COMMON_SIZE; i++) {
    MemoryBlock *block = blocks[i];
    for (; block; block = block->next) {
      Finalizer *fn = block->finalizers;
      for (; fn ; fn = fn->next) {
	unsigned long p;
	  
	/* Always mark data associated with finalization: */
	p = PTR_TO_INT(&fn->data);
	PUSH_COLLECT(p, p + PTR_SIZE, 0);

	/* If not eager, mark data reachable from finalized block: */
	if (!fn->eager) {
	  int pos, apos;
	  int bit, fbit;

	  pos = fn->u.pos;
	  apos = POS_TO_UNMARK_INDEX(pos);
	  bit = POS_TO_UNMARK_BIT(pos);
	  fbit = POS_TO_FREE_BIT(pos);
	  
	  if (NOT_MARKED(block->free[apos] & bit)
	      && _NOT_FREE(block->free[apos] & fbit)) {
	    int size = block->size;
	    
	    if (!atomic) {
	      p = block->start + (pos * size);
	      if (fn->ignore_self)
		push_collect_ignore(p, p + size, p);
	      else {
		PUSH_COLLECT(p, p + size, 0);
	      }

#if WATCH_FOR_FINALIZATION_CYCLES
	      collect();
	      if (IS_MARKED(block->free[apos] & bit))
		FPRINTF(STDERR, "cycle: %lx\n", p);
#endif
	    }
	  }
	}
      }
    }
  }

  collect();
}

static void enqueue_fn(Finalizer *fn)
{
  /* DO NOT COLLECT FROM collect_stack DURING THIS PROCEDURE */

  unsigned long p;

  if (last_queued_finalizer) {
    fn->prev = last_queued_finalizer;
    fn->prev->next = fn;
    fn->next = NULL;
  } else {
    fn->next = queued_finalizers;
    if (fn->next)
      fn->next->prev = fn;
    queued_finalizers = fn;
  }
  last_queued_finalizer = fn;

  /* Need to mark watched as in-use, now: */
  /* (if this finalizer is eager, block contents are now marked too) */
  p = PTR_TO_INT(&fn->u.watch);
  PUSH_COLLECT(p, p + PTR_SIZE, 0);
}

static void queue_chunk_finalizeable(MemoryChunk *c, int eager)
{
  /* DO NOT COLLECT FROM collect_stack DURING THIS PROCEDURE */

  for (; c; c = c->next) {
    if (c->finalizers && !c->marked) {
      Finalizer *fn = c->finalizers;

      if (fn->eager == eager) {
	c->finalizers = NULL;

	fn->u.watch = INT_TO_PTR(c->start);
	enqueue_fn(fn);

	if (eager) {
	  /* Always mark data associated with finalization: */
	  unsigned long p = PTR_TO_INT(&fn->data);
	  PUSH_COLLECT(p, p + PTR_SIZE, 0);
	}
      }
    }
  }
}

static void queue_common_finalizeable(MemoryBlock **blocks, int eager)
{
  /* DO NOT COLLECT FROM collect_stack DURING THIS PROCEDURE */

  int i;
  
  for (i = 0; i < NUM_COMMON_SIZE; i++) {
    MemoryBlock *block = blocks[i];
    for (; block; block = block->next) {
      Finalizer *fn = block->finalizers, *next;
      
      for (; fn; fn = next) {
	int pos, apos;
	int bit;
	  
	next = fn->next;

	pos = fn->u.pos;
	apos = POS_TO_UNMARK_INDEX(pos);
	bit = POS_TO_UNMARK_BIT(pos);
	
	if (NOT_MARKED(block->free[apos] & bit)) {
	  unsigned long p;
	
	  if (fn->eager == eager) {
	    if (fn->prev)
	      fn->prev->next = fn->next;
	    else
	      block->finalizers = fn->next;
	    if (fn->next)
	      fn->next->prev = fn->prev;
	    
	    p = block->start + (pos * block->size);
	    fn->u.watch = INT_TO_PTR(p);
	    enqueue_fn(fn);

	    if (eager) {
	      /* Always mark data associated with finalization: */
	      p = PTR_TO_INT(&fn->data);
	      PUSH_COLLECT(p, p + PTR_SIZE, 0);
	    }
	  }
	}
      }
    }
  }
}

static void do_disappear_and_finals()
{
  DisappearingLink *dl, *next;
  Finalizer *fn;
  int j;

  /* Mark data in (not-yet-finalized) queued finalizable */
  for (fn = queued_finalizers; fn; fn = fn->next) {
    unsigned long p;

    p = PTR_TO_INT(&fn->u.watch);
    PUSH_COLLECT(p, p + PTR_SIZE, 0);

    p = PTR_TO_INT(&fn->data);
    PUSH_COLLECT(p, p + PTR_SIZE, 0);
  }
  collect();

#if !NO_DISAPPEARING
  /* Do disappearing: */
  for (dl = disappearing; dl; dl = next) {
    void *watch;
    int size;

    next = dl->next;

    watch = (dl->watch ? dl->watch : *dl->disappear);

    size = 0;
    if (watch && !find_ptr(watch, &size, NULL, NULL, NULL, 0)) {
      /* was the pointer allocated at all? */
      if (size) {
	/* It's gone: */
	if (dl->watch) {
	  /* disappear is done. */
	  if (dl->prev)
	    dl->prev->next = dl->next;
	  else
	    disappearing = dl->next;
	  if (dl->next)
	    dl->next->prev = dl->prev;
	  *dl->disappear = NULL;

	  mem_real_use -= sizeof(DisappearingLink);
	  free_managed(dl);
	  --GC_dl_entries;
	} else {
	  /* We'll need to restore this one: */
	  dl->saved_value = *dl->disappear;
	  *dl->disappear = NULL;
	}
      }
    }
  }
#endif

  /* Queue unreachable eager finalizable: */  
  /* DO NOT COLLECT FROM collect_stack UNTIL AFTER THIS LOOP */
  /* (Otherwise, some ready eager finalizations may not be queued.) */
  for (j = 0; j < num_common_sets; j++) {
    queue_chunk_finalizeable(*(common_sets[j]->othersptr), 1);
    queue_common_finalizeable(common_sets[j]->blocks, 1);
  }
  collect();

  /* Mark reachable from (non-eager) finalized blocks: */
  for (j = 0; j < num_common_sets; j++) {
    mark_chunks_for_finalizations(*(common_sets[j]->othersptr));
    mark_common_for_finalizations(common_sets[j]->blocks, common_sets[j]->atomic);
  }

  /* Queue unreachable (non-eager) finalizable: */  
  for (j = 0; j < num_common_sets; j++) {
    queue_chunk_finalizeable(*(common_sets[j]->othersptr), 0);
    queue_common_finalizeable(common_sets[j]->blocks, 0);
  }
  collect();

  /* Restore disappeared links where watch value is NULL: */
  for (dl = disappearing; dl; dl = next) {
    next = dl->next;
    if (!dl->watch && dl->saved_value) {
      /* Restore disappearing value and deregister */
      *dl->disappear = dl->saved_value;
      dl->saved_value = NULL;
    }
  }
  
  /* Deregister dangling disappearings: */
  for (dl = disappearing; dl; dl = next) {
    int size;

    next = dl->next;
    
    size = 0;
    if (!find_ptr(dl->disappear, &size, NULL, NULL, NULL, 0) && size) {
      /* Found it, but it was unmarked. Deregister disappearing. */
      if (dl->prev)
	dl->prev->next = dl->next;
      else
	disappearing = dl->next;
      if (dl->next)
	dl->next->prev = dl->prev;

      mem_real_use -= sizeof(DisappearingLink);
      free_managed(dl);
      --GC_dl_entries;
    }
  }

  if (GC_custom_finalize)
    GC_custom_finalize();
}

static int compare_roots(const void *a, const void *b)
{
  if (*(unsigned long *)a < *(unsigned long *)b)
    return -1;
  else
    return 1;
}

static void sort_and_merge_roots()
{
  static int counter = 0;
  int i, offset, top;

  if (roots_count < 4)
    return;

  /* Only try this every 5 collections or so: */
  if (counter--)
    return;
  counter = 5;

  qsort(roots, roots_count >> 1, 2 * sizeof(unsigned long), compare_roots);
  offset = 0;
  top = roots_count;
  for (i = 2; i < top; i += 2) {
    if ((roots[i - 2 - offset] <= roots[i])
	&& ((roots[i - 1 - offset] + (PTR_ALIGNMENT - 1)) >= roots[i])) {
      /* merge: */
      if (roots[i + 1] > roots[i - 1 - offset])
	roots[i - 1 - offset] = roots[i + 1];
      offset += 2;
      roots_count -= 2;
    } else if (offset) {
      /* compact: */
      roots[i - offset] = roots[i];
      roots[i + 1 - offset] = roots[i + 1];
    }
  }
}

static void run_finalizers(void)
{
  static int doing = 0;
  Finalizer *fn;
  void *s;

  /* don't allow nested finalizations */
  if (doing)
    return;
  doing++;

#if !NO_FINALIZING
  while (queued_finalizers) {
    fn = queued_finalizers;
    queued_finalizers = fn->next;
    if (!fn->next)
      last_queued_finalizer = NULL;

    s = fn->u.watch;
    
#if PAD_BOUNDARY_BYTES
    s = PAD_FORWARD(s);
#endif

    fn->f(s, fn->data);

    mem_real_use -= sizeof(Finalizer);
    free_managed(fn);
    --GC_fo_entries;
  }
#endif

  doing--;
}

#if ALLOW_TRACE_COUNT
static int traced_from_roots, traced_from_stack, traced_from_uncollectable, traced_from_finals;
#endif

#if TIME
# define PRINTTIME(x) FPRINTF x
#else
# define PRINTTIME(x) /* empty */
#endif

/* Immitate Boehm's private GC call; used by MzScheme */
void GC_push_all_stack(void *sp, void *ep)
{
  unsigned long s, e;

  s = PTR_TO_INT(sp);
  e = PTR_TO_INT(ep);

  PUSH_COLLECT(s, e, 0);
}

void do_GC_gcollect(void *stack_now)
{
  long root_marked;
  int j;

#if SGC_STD_DEBUGGING
  long orig_mem_use = mem_use;
  FPRINTF(STDERR, "gc at %ld (%ld): %ld\n",
	  mem_use, sector_mem_use, 
# if GET_MEM_VIA_SBRK
	  (long)sbrk(0)
# else
#  if defined(WIN32) && AUTO_STATIC_ROOTS_IF_POSSIBLE
	  total_memory_use()
#  else
	  0
#  endif
# endif
	  );
# if SHOW_SECTOR_MAPS_AT_GC
  dump_sector_map("");
# endif
#endif

  if (!GC_stackbottom) {
    /* Stack position not yet initialize; delay collection */
    if (mem_use)
      mem_limit = MEM_USE_FACTOR * mem_use;
    return;
  }

  if (!initialized)
    GC_initialize();

  if (!statics_setup)
    init_static_variables();

  if (GC_collect_start_callback)
    GC_collect_start_callback();

#if CHECK_COLLECTING
  collecting_now = 1;
#endif

#if !NO_COLLECTIONS

# if ALWAYS_TRACE && ALLOW_TRACE_COUNT
  collecting_with_trace_count = 1;
# endif

# if CHECK
  cmn_count = chk_count = 0;
# endif

  PRINTTIME((STDERR, "gc: common init start: %ld\n", scheme_get_process_milliseconds()));

  for (j = 0; j < num_common_sets; j++) {
# if ALLOW_SET_LOCKING
    if (!common_sets[j]->locked) {
# endif
      collect_init_chunk(*(common_sets[j]->othersptr),
			 common_sets[j]->uncollectable);
      collect_init_common(common_sets[j]->blocks,
			  common_sets[j]->uncollectable);
# if ALLOW_SET_LOCKING
    }
# endif
  }

# if CHECK
  if (num_chunks != chk_count) {
    FPRINTF(STDERR, "bad chunk count: %ld != %ld\n", num_chunks, chk_count);
  }

  if (num_blocks != cmn_count) {
    FPRINTF(STDERR, "bad block count: %ld != %ld\n", num_blocks, cmn_count);
  }
# endif

# if PRINT
  FPRINTF(STDERR, "gc at %ld (%ld)\n", mem_use, mem_real_use);
  FPRINTF(STDERR,
	  "low: %lx hi: %lx blocks: %ld chunks: %ld\n", 
	  low_plausible, high_plausible, 
	  num_blocks, num_chunks);
# endif

  mem_use = 0;

  sort_and_merge_roots();

# if ALLOW_TRACE_COUNT
  init_trace_stack(&collect_trace_stack);
  init_trace_stack(&collect_wait_trace_stack);
  collect_start_tracing = 0;
  collect_end_tracing = -1;
# endif
# if ALLOW_TRACE_PATH
  init_trace_stack(&collect_trace_path_stack);
# endif

  prepare_collect_temp();

  collect_stack_size = roots_count ? COLLECT_STACK_FRAME_SIZE * roots_count : 10;
  collect_stack_count = 0;
  collect_stack = (unsigned long *)realloc_collect_temp(NULL,
							0,
							sizeof(unsigned long) 
							* (collect_stack_size + 1));
  for (j = 0; j < roots_count; j += 2) {
    collect_stack[collect_stack_count++] = roots[j];
    collect_stack[collect_stack_count++] = roots[j + 1];
    collect_stack[collect_stack_count++] = 0;
  }

  PRINTTIME((STDERR, "gc: root collect start: %ld\n", scheme_get_process_milliseconds()));

# if ALLOW_TRACE_COUNT
  collect_trace_count = 0;
  mem_traced = 0;
# endif

# if ALLOW_TRACE_PATH
  current_trace_source = "root";
# endif

  collect();

# if ALLOW_SET_LOCKING
  for (j = 0; j < num_common_sets; j++) {
    if (common_sets[j]->locked) {
      int a = common_sets[j]->atomic;
      push_locked_chunk(*(common_sets[j]->othersptr), a);
      push_locked_common(common_sets[j]->blocks, a);
    }
  }

  collect();
# endif

# if ALLOW_TRACE_COUNT
  traced_from_roots = collect_trace_count;
  collect_trace_count = 0;
# endif

  root_marked = mem_use;

  push_stack(stack_now);
  
  collect_end_stackbased = collect_stack_count;
# if PRINT && 0
  FPRINTF(STDERR, "stack until: %ld\n", collect_end_stackbased);
# endif

# if ALLOW_TRACE_PATH
  current_trace_source = "stack";
# endif

  PRINTTIME((STDERR, "gc: stack collect start: %ld\n", scheme_get_process_milliseconds()));

  collect();

  PRINTTIME((STDERR, "gc: \"other roots\" start: %ld\n", scheme_get_process_milliseconds()));

  if (GC_push_other_roots) {
    GC_push_other_roots();
    collect_end_stackbased = collect_stack_count;
  }

# if ALLOW_TRACE_PATH
  current_trace_source = "xstack";
# endif

  collect();

# if ALLOW_TRACE_COUNT
  traced_from_stack = collect_trace_count;
  collect_trace_count = 0;
# endif

  PRINTTIME((STDERR, "gc: uncollectable start: %ld\n", scheme_get_process_milliseconds()));

  for (j = 0; j < num_common_sets; j++)
    if (common_sets[j]->uncollectable)
      if (!common_sets[j]->atomic
# if ALLOW_TRACE_COUNT
	  || collecting_with_trace_count
# endif
	  ) {
	push_uncollectable_chunk(*(common_sets[j]->othersptr), common_sets[j]);
	push_uncollectable_common(common_sets[j]->blocks, common_sets[j]);
      }

# if ALLOW_TRACE_PATH
  current_trace_source = "uncollectable";
# endif

  collect();

# if ALLOW_TRACE_COUNT
  traced_from_uncollectable = collect_trace_count;
  collect_trace_count = 0;
# endif
  
  PRINTTIME((STDERR, "gc: queue finalize start: %ld\n", scheme_get_process_milliseconds()));

# if ALLOW_TRACE_PATH
  current_trace_source = "finalization";
# endif

  do_disappear_and_finals();

# if ALLOW_TRACE_COUNT
  traced_from_finals = collect_trace_count;
# endif

  PRINTTIME((STDERR, "gc: finish start: %ld\n", scheme_get_process_milliseconds()));

  low_plausible = high_plausible = 0;

  for (j = 0; j < num_common_sets; j++) {
    collect_finish_chunk(common_sets[j]->othersptr, common_sets[j]);
    collect_finish_common(common_sets[j]->blocks, 
			  common_sets[j]->block_ends,
			  common_sets[j]);
  }

  PRINTTIME((STDERR, "gc: all done: %ld\n", scheme_get_process_milliseconds()));

# if PRINT
  FPRINTF(STDERR,
	  "done %ld (%ld), %ld from stack\n", mem_use, mem_real_use,
	  mem_use - root_marked);
# endif

  if (mem_use)
    mem_limit = MEM_USE_FACTOR * mem_use;

  free_collect_temp(collect_stack);

# if ALLOW_TRACE_COUNT
  done_trace_stack(&collect_trace_stack);
  done_trace_stack(&collect_wait_trace_stack);
# endif
# if ALLOW_TRACE_PATH
  done_trace_stack(&collect_trace_path_stack);
# endif

#else
  if (mem_use)
    mem_limit = MEM_USE_FACTOR * mem_use;
#endif

#if SGC_STD_DEBUGGING
  FPRINTF(STDERR, "done  %ld (%ld); recovered %ld\n",
	  mem_use, sector_mem_use, orig_mem_use - mem_use);
# if SHOW_SECTOR_MAPS_AT_GC
  dump_sector_map("                            ");
# endif
#endif

#if STAMP_AND_REMEMBER_SOURCE
  stamp_clock++;
#endif

#if CHECK_COLLECTING
  collecting_now = 0;
#endif

  if (GC_collect_end_callback)
    GC_collect_end_callback();

  /* Run queued finalizers. Garbage collections may happen: */
  PRINTTIME((STDERR, "gc: finalize start: %ld\n", scheme_get_process_milliseconds()));
  run_finalizers();
  PRINTTIME((STDERR, "gc: finalize end: %ld\n", scheme_get_process_milliseconds()));
}

void GC_gcollect(void)
{
  long dummy;

  if (!sector_pagetables)
    return;

  FLUSH_REGISTER_WINDOWS;
  if (!setjmp(buf))
    do_GC_gcollect((void *)&dummy);
}

int GC_trace_count(int *stack, int *roots, int *uncollectable, int *final)
{
#if ALLOW_TRACE_COUNT
  int j;

  if (!sector_pagetables)
    return 0;

  for (j = 0; j < num_common_sets; j++) {
    if (common_sets[j]->trace_init)
      common_sets[j]->trace_init();
  }

  collecting_with_trace_count = 1;
  GC_gcollect();
  collecting_with_trace_count = 0;

  if (stack)
    *stack = traced_from_stack;
  if (roots)
    *roots = traced_from_roots;
  if (uncollectable)
    *uncollectable = traced_from_uncollectable;
  if (final)
    *final = traced_from_finals;

  for (j = 0; j < num_common_sets; j++) {
    if (common_sets[j]->trace_done)
      common_sets[j]->trace_done();
  }

  return mem_traced;
#else
  return 0;
#endif
}

void GC_trace_path(void)
{
#if ALLOW_TRACE_PATH
  int j;

  if (!sector_pagetables)
    return;

  for (j = 0; j < num_common_sets; j++) {
    if (common_sets[j]->trace_init)
      common_sets[j]->trace_init();
  }

  trace_path_buffer_pos = 0;

  collecting_with_trace_path = 1;
  GC_gcollect();
  collecting_with_trace_path = 0;

  for (j = 0; j < num_common_sets; j++) {
    if (common_sets[j]->trace_done)
      common_sets[j]->trace_done();
  }
#endif
}

void GC_store_path(void *v, unsigned long src, void *path_data)
{
#if ALLOW_TRACE_PATH
  TraceStack *s = (TraceStack *)path_data;
  int len, i;

  if (trace_path_buffer_pos < 0)
    return;

  len = s->count / 3;
  if (len * 2 + 3 > (TRACE_PATH_BUFFER_SIZE - trace_path_buffer_pos - 7)) {
    trace_path_buffer[trace_path_buffer_pos++] = (void *)2;
    trace_path_buffer[trace_path_buffer_pos++] = "truncated";
    trace_path_buffer[trace_path_buffer_pos++] = 0;
    trace_path_buffer[trace_path_buffer_pos++] = v;
    trace_path_buffer[trace_path_buffer_pos++] = 0;
    trace_path_buffer[trace_path_buffer_pos] = 0;
    trace_path_buffer_pos = -1;
    return;
  }

  if (len) {
    unsigned long prev = 0;

    trace_path_buffer[trace_path_buffer_pos++] = (void *)(len + 2);
    trace_path_buffer[trace_path_buffer_pos++] = current_trace_source;
    trace_path_buffer[trace_path_buffer_pos++] = 0;
    for (i = 1; len--; i += 3) {
      trace_path_buffer[trace_path_buffer_pos++] = (void *)s->stack[i];
      trace_path_buffer[trace_path_buffer_pos++] = 0;

      if (i > 1) {
	unsigned long diff;
	if (s->stack[i + 1])
	  diff = ((unsigned long)s->stack[i + 1]) - prev;
	else
	  diff = 0;
	trace_path_buffer[trace_path_buffer_pos - 3] = (void *)diff;
      }
      prev = (unsigned long)s->stack[i];
    }

    trace_path_buffer[trace_path_buffer_pos - 1] = (void *)(src - prev);

    trace_path_buffer[trace_path_buffer_pos++] = v;
    trace_path_buffer[trace_path_buffer_pos++] = 0;
    trace_path_buffer[trace_path_buffer_pos] = 0;
  }
#endif
}

void **GC_get_next_path(void **prev, int *len)
{
  void **p;

  if (!prev)
    p = trace_path_buffer;
  else
    p = prev + (2 * (((long *)prev)[-1]));
    
  *len = *(long *)p;
  if (!*len)
    return NULL;

  return p + 1;
}

void GC_clear_paths(void)
{
  int i;

  for (i = 0; i < TRACE_PATH_BUFFER_SIZE; i++)
    trace_path_buffer[i] = NULL;
}

/**********************************************************************/

#if FPRINTF_USE_PRIM_STRINGOUT

#if PRIM_STRINGOUT_AS_FWRITE
void GC_prim_stringout(char *s, int len)
{
  fwrite(s, len, 1, stderr);
}
#else
# if PRIM_STRINGOUT_AS_WINDOWS_CONSOLE
void GC_prim_stringout(char *s, int len)
{
  static HANDLE console;
  DWORD wrote;

  if (!console) {
	COORD size;
    AllocConsole();
    console = GetStdHandle(STD_OUTPUT_HANDLE);
	size.X = 90;
	size.Y = 500;
	SetConsoleScreenBufferSize(console, size);
  }

  WriteConsole(console, s, len, &wrote, NULL);
}
# else
extern void GC_prim_stringout(char *s, int len);
# endif
#endif

#include <stdarg.h>
#include <ctype.h>

#define NP_BUFSIZE 512

/* Non-allocating printf. */
static void sgc_fprintf(int ignored, const char *c, ...)
{
  char buffer[NP_BUFSIZE];
  int pos;
  va_list args;

  va_start(args, c);

  pos = 0;
  while (*c) {
    if (*c == '%') {
      int len = -1, slen;
      int islong = 0;
      char *s;

      if (pos) {
	GC_prim_stringout(buffer, pos);
	pos = 0;
      }

      c++;
      if (isdigit(*c)) {
	len = 0;
	while (isdigit(*c)) {
	  len = (len * 10) + (*c - '0');
	  c++;
	}
      }

      if (*c == 'l') {
	islong = 1;
	c++;
      }
      
      switch (*c) {
      case 'd':
      case 'x':
	{
	  long v;
	  int d, i;

	  if (islong) {
	    v = va_arg(args, long);
	  } else {
	    v = va_arg(args, int);
	  }
	  
	  if (!v) {
	    s = "0";
	    slen = 1;
	  } else {
	    int neg = 0;

	    i = NP_BUFSIZE - 2;
	    
	    if (v < 0) {
	      neg = 1;
	      v = -v;
	    }

	    d = (((*c) == 'd') ? 10 : 16);
	    while (v) {
	      int digit = (v % d);
	      if (digit < 10)
		digit += '0';
	      else
		digit += 'a' - 10;
	      buffer[i--] = digit;
	      v = v / d;
	    }
	    if (neg)
	      buffer[i--] = '-';

	    s = buffer + i + 1;
	    slen = (NP_BUFSIZE - 2) - i;
	  }
	}
	break;
      case 's':
	s = va_arg(args, char*);
	slen = strlen(s);
	break;
      default:
	s = "???";
	slen = 3;
	break;
      }

      c++;

      if (len != -1) {
	if (slen > len)
	  slen = len;
	else {
	  int i;
	  for (i = slen; i < len; i++)
	    GC_prim_stringout(" ", 1);
	}
      }
      
      if (slen)
	GC_prim_stringout(s, slen);
    } else {
      if (pos == (NP_BUFSIZE - 1)) {
	GC_prim_stringout(buffer, pos);
	pos = 0;
      }
      buffer[pos++] = *(c++);
    }
  }

  if (pos)
    GC_prim_stringout(buffer, pos);

  /* Suggest a flush: */
  GC_prim_stringout(NULL, 0);

  va_end(args);
}

#endif


