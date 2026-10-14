#ifndef CEMU_H
#define CEMU_H

#include "hp48.h"
#include "hp48_emu.h"
#include "debugger.h"
#include "binio.h"
#include "x48.h"

/* out buffer length for emu_fill_screen_data: (14 header rows + 128 LCD
 * rows) x 262 columns, matching the Android mainScreen bitmap exactly. */
#define EMU_SCREEN_BUF_LEN ((14 + 128) * 262)

void emu_set_config_dir(const char *path);
void emu_set_blank_color(unsigned short color);
void emu_flip_screen(void);
int  emu_fill_screen_data(unsigned short *out, unsigned char *ann_out);

#endif
