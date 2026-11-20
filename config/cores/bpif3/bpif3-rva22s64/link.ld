/* ACT 4.1 linker layout for SpacemiT K1 / Banana Pi BPI-F3. */
/* Above the first GiB: Sv tests remap virtual addresses 0..1 GiB (e.g. Sv_sv39_VA_all_zeros), which
   would unmap test code linked there, including the S-mode trap handler. Inside the runner's DRAM
   window (BOARD_RAM_BASE..BOARD_RAM_LIMIT, 0x04000000..0x80000000) and Sail's RAM region. */
RAM_ORIGIN = 0x50000000;
RAM_LENGTH = 0x08000000;
TEST_BASE = RAM_ORIGIN;
NUM_HARTS = 1;
STACK_SIZE = 0x20000;

OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

MEMORY
{
  ram (rwx) : ORIGIN = RAM_ORIGIN, LENGTH = RAM_LENGTH
}

PROVIDE(__stack_size = STACK_SIZE);
PROVIDE(__num_harts = NUM_HARTS);

SECTIONS
{
  ASSERT(TEST_BASE >= ORIGIN(ram) && TEST_BASE < ORIGIN(ram) + LENGTH(ram), "TEST_BASE is outside RAM; update link.ld and the matching sail.json memory region")

  .text.init   TEST_BASE : { *(.text.init) } > ram
  .text.rvtest . : { *(.text.rvtest) *(.text.rvtest.*) } > ram

  . = ALIGN(0x4000);
  .rodata . : { *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) } > ram
  .data   . : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) } > ram

  . = ALIGN(16);
  .bss . : {
    __bss_start = .;
    *(.sbss) *(.sbss.*) *(.bss) *(.bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
  } > ram

  . = ALIGN(16);
  __stack_bottom = .;
  . += __stack_size * __num_harts;
  __stack_top = .;

  . = ALIGN(0x1000);
  .text.rvmodel . : { *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*) } > ram

  . = ALIGN(0x1000);
  _end = .;

  ASSERT(_end <= ORIGIN(ram) + LENGTH(ram), "ACT ELF exceeds the configured RAM region")

  /* K1 timer compare is outside the ELF RAM region and occupies no bytes. */
  .k1_periph_mtimecmp 0xE4004000 (NOLOAD) : { _k1_mtimecmp = .; }
}
