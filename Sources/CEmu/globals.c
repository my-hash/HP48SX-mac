/*
 *  This file is part of x48, an emulator of the HP-48sx Calculator.
 *  Copyright (C) 1994  Eddie C. Dost  (ecd@dressler.de)
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/* Trimmed for the macOS port: globals + save_options() kept, main() and
 * every Java_org_czo_droid48sx_X48_* JNI function dropped (the Swift
 * EmulatorBridge drives the emulate loop directly instead). */

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <sys/time.h>
#include <fcntl.h>
#include <locale.h>

#include "x48.h"
#include "hp48.h"
#include "binio.h"
#include "debugger.h"
#include "hp48_emu.h"

char  *progname;
char  *res_name;
char  *res_class;

int    saved_argc;
char **saved_argv;

saturn_t saturn;
int nb;
int exit_state = 1;

void
save_options(int argc, char **argv)
{
  int l;

  saved_argc = argc;
  saved_argv = (char **)malloc((argc + 2) * sizeof(char *));
  if (saved_argv == (char **)0)
    {
      LOGE( "%s: malloc failed in save_options(), exit\n", progname);
      exit (1);
    }
  saved_argv[argc] = (char *)0;
  while (argc--)
    {
      l = strlen(argv[argc]) + 1;
      saved_argv[argc] = (char *)malloc(l);
      if (saved_argv[argc] == (char *)0)
        {
          LOGE( "%s: malloc failed in save_options(), exit\n",
                  progname);
          exit (1);
        }
      memcpy(saved_argv[argc], argv[argc], l);
    }
}

char config_dir[1024];

void
emu_set_config_dir(const char *path) {
	strcpy(config_dir, path);
}

/* Test-only: exposes whether a memory controller is in its power-on
 * "unconfigured" state. do_reset() (actions.c) forces this back to the
 * power-on default for all 6 controllers; read_files() (init.c), on a
 * successful load, restores whatever the saved session had configured.
 * Calling do_reset() unconditionally after init_emulator() -- which
 * init.c:1806-1826 shows always returns 0, on both its success and
 * fresh-boot paths -- re-defaults this right after a real restore,
 * which is how a saved session's stack gets silently discarded. */
int
emu_debug_mem_cntl_unconfigured(int index) {
	return saturn.mem_cntl[index].unconfigured;
}

/* Test-only: forces emulate()'s "while (!enter_debugger && exit_state)"
 * loop to return early, the same way a real illegal instruction would. */
void
emu_debug_trigger_illegal_instruction(void) {
	enter_debugger = 2; /* ILLEGAL_INSTRUCTION, debugger.h */
}
