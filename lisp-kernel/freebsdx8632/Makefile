#
# Copyright 2005-2006 Clozure Associates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SVN_REVISION != svnversion

VPATH = ..
RM = /bin/rm
AS = as
M4 = m4
ASFLAGS = --32
M4FLAGS = -DFREEBSD -DX86 -DX8632 -DHAVE_TLS
CDEFINES = -DFREEBSD -D_REENTRANT -DX86 -DX8632 -D_GNU_SOURCE -DHAVE_TLS -DSVN_REVISION="$(SVN_REVISION)"
CDEBUG = -g
COPT = #-O2
# Once in a while, -Wformat says something useful.  The odds are against that,
# however.
WFORMAT = -Wno-format
PLATFORM_H = platform-freebsdx8632.h



SPOBJ = pad.o x86-spjump32.o x86-spentry32.o x86-subprims32.o
ASMOBJ = x86-asmutils32.o imports.o

COBJ  = pmcl-kernel.o gc-common.o  x86-gc.o bits.o  x86-exceptions.o \
	x86-utils.o \
	image.o thread_manager.o lisp-debug.o memory.o unix-calls.o

DEBUGOBJ = lispdcmd.o plprint.o plsym.o xlbt.o x86_print.o
KERNELOBJ= $(COBJ) x86-asmutils32.o  imports.o

SPINC =	lisp.s m4macros.m4 x86-constants.s x86-macros.s errors.s x86-uuo.s \
	x86-constants32.s lisp_globals.s

CHEADERS = area.h bits.h x86-constants.h lisp-errors.h gc.h lisp.h \
	lisp-exceptions.h lisp_globals.h macros.h memprotect.h image.h \
	x86-utils.h \
	threads.h x86-constants32.h x86-exceptions.h $(PLATFORM_H)

.if $(MACHINE) == "amd64"
CROSS = -B/usr/lib32
.endif

KSPOBJ = $(SPOBJ)
all:	../../fx86cl


OSLIBS = -lm -lthr $(CROSS)

.s.o:
	$(M4) $(M4FLAGS) -I../ $< | $(AS)  $(ASFLAGS) -o $@
.c.o:
	$(CC) -include ../$(PLATFORM_H) -c $< $(CDEFINES) $(CDEBUG) $(COPT) $(WFORMAT) -m32 -o $@

LINKSCRIPTFILE = # 
LINKSCRIPT =  # -T $(LINKSCRIPTFILE)

../../fx86cl:	$(KSPOBJ) $(KERNELOBJ) $(DEBUGOBJ) $(LINKSCRIPTFILE)
	$(CC) -m32 $(CDEBUG)  -Wl,--export-dynamic  $(LINKSCRIPT)  -o $@  $(KSPOBJ) $(KERNELOBJ) $(DEBUGOBJ) $(OSLIBS)


$(SPOBJ): $(SPINC)
$(ASMOBJ): $(SPINC)
$(COBJ): $(CHEADERS)
$(DEBUGOBJ): $(CHEADERS) lispdcmd.h

cclean:
	$(RM) -f $(KERNELOBJ) $(DEBUGOBJ) ../../fx86cl

clean:	cclean
	$(RM) -f $(SPOBJ)

strip:	../../fx86cl
	strip -g ../../fx86cl
