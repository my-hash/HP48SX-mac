#ifndef CEMU_H
#define CEMU_H

/* Self-contained on purpose: SwiftPM only exposes this target's `include/`
 * directory to consumers (Swift's module map for CEmu can't see sibling
 * headers like hp48.h that live in the target's source root, even with a
 * headerSearchPath setting -- confirmed empirically), so this header
 * re-declares the plain-C surface instead of #include-ing the vendored
 * legacy headers. Signatures match hp48.h/hp48_emu.h/debugger.h/binio.h/
 * x48.h exactly. */

extern char config_dir[1024];
extern int  exec_flags;
extern int  exit_state;

int  init_emulator(void);
void init_active_stuff(void);
int  emulate(void);
int  emulate_debug(void);
int  debug(void);
void do_reset(void);
int  write_files(void);
int  button_pressed(int b);
int  button_released(int b);
int  read_bin_file(char *filename);

/* out buffer length for emu_fill_screen_data: (14 header rows + 128 LCD
 * rows) x 262 columns, matching the Android mainScreen bitmap exactly.
 * A plain `static const int` imports into Swift reliably; a `#define`
 * macro expanding to an arithmetic expression does not (confirmed: Swift
 * rejected it with "structure not supported"). */
static const int EMU_SCREEN_BUF_LEN = (14 + 128) * 262;

void emu_set_config_dir(const char *path);
void emu_set_blank_color(unsigned short color);
void emu_flip_screen(void);
int  emu_fill_screen_data(unsigned short *out, unsigned char *ann_out);

#endif
