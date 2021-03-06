#!/bin/sh

LANG=C

opr="$1"
shift
if [ -z "$opr" ]; then
    echo "ERROR: Missing operation" > /dev/stderr
    exit 1
fi

tfn="$1"
shift
if [ -z "$tfn" ]; then
    echo "ERROR: Missing target filename" > /dev/stderr
    exit 1
fi

ofn="$1"
lfn="$2"

if [ -z "$ofn" ]; then
    echo "ERROR: Missing object file argument" > /dev/stderr
    exit 1
fi

if [ "$opr" = "sdtstub" ]; then
    ${NM} -u $* | \
	grep __dtrace_probe_ | sort | uniq | \
	${AWK} '{
		    printf("\t.globl %s\n\t.type %s,@function\n%s:\n",
			   $2, $2, $2);
		    count++;
		}

		END {
		    if (count)
			print "\tret";
		    else
			exit(1);
		}' > $tfn
    exit 0
fi

if [ "$opr" != "sdtinfo" ]; then
    echo "ERROR: Invalid operation, should be sdtstub or sdtinfo" > /dev/stderr
    exit 1
fi

(
    objdump -htr "$ofn" | \
	awk -v lfn="${lfn}" \
	    '/^Sections:/ {
		 getline;
		 getline;
		 while ($0 !~ /SYMBOL/) {
		     sect = $2;
		     addr = $6;

		     getline;
		     if (/CODE/)
			 sectbase[sect] = addr;

		     getline;
		 }
		 next;
	     }

	     $3 == "F" {
		 printf "%16s %s F %s\n", $4, $1, $6;

		 if (!lfn || lfn == "kmod")
		     printf "%s t %s\n", $1, $6;

		 next;
	     }

	     /^RELOC/ {
		 sub(/^[^\[]+\[/, "");
		 sub(/].*$/, "");
		 sect = $1;
		 next;
	     }

	     /__dtrace_probe_/ && sect !~ /debug/ {
		 $3 = substr($3, 16);
		 sub(/-.*$/, "", $3);
		 printf "%16s %s R %s %s\n", sect, $1, $3, sectbase[sect];
		 next;
	     }' | \
	sort
    [ "x${lfn}" != "x" -a "x${lfn}" != "xkmod" ] && nm ${lfn}
) | \
    awk -v lfn="${lfn}" \
	'function addl(v0, v1, v0h, v0l, v1h, v1l, d, tmp) {
	     tmp = $0;
	     if (length(v0) > 8) {
		 d = length(v0);
		 v0h = strtonum("0x"substr(v0, 1, d - 8));
		 v0l = strtonum("0x"substr(v0, d - 8 + 1));
		 d = length(v1);
		 v1h = strtonum("0x"substr(v1, 1, d - 8));
		 v1l = strtonum("0x"substr(v1, d - 8 + 1));

		 v0h += v1h;
		 v0l += v1l;

		 d = sprintf("%x", v0l);
		 if (length(d) > 8)
		     v0h++;

		 d = sprintf("%x%x", v0h, v0l);
	     } else {
		 v0 = strtonum("0x"v0);
		 v1 = strtonum("0x"v1);
		 d = sprintf("%x", v0 + v1);
	     }
	     $0 = tmp;

	     return d;
	 }

	 function subl(v0, v1, v0h, v0l, v1h, v1l, d, tmp) {
	     tmp = $0;
	     if (length(v0) > 8) {
		 d = length(v0);
		 v0h = strtonum("0x"substr(v0, 1, d - 8));
		 v0l = strtonum("0x"substr(v0, d - 8 + 1));
		 d = length(v1);
		 v1h = strtonum("0x"substr(v1, 1, d - 8));
		 v1l = strtonum("0x"substr(v1, d - 8 + 1));

		 if (v0l > v1l) {
		     if (v0h >= v1h) {
			 d = sprintf("%x%x", v0h - v1h, v0l - v1l);
		     } else {
		         printf "#error Invalid addresses: %x vs %x", v0, v1 \
								> /dev/stderr;
			 errc++;
		     }
		 } else {
		     printf "#error Invalid addresses: %x vs %x", v0, v1 \
								> /dev/stderr;
		     errc++;
		 }
	     } else {
		 v0 = strtonum("0x"v0);
		 v1 = strtonum("0x"v1);
		 d = sprintf("%x", v0 - v1);
	     }
	     $0 = tmp;

	     return d;
	 }

	 BEGIN {
	     if (lfn != "kmod") {
		 print "#include <asm/types.h>";
		 print "#if BITS_PER_LONG == 64";
		 print "# define PTR .quad";
		 print "# define ALGN .align 8";
		 print "#else";
		 print "# define PTR .long";
		 print "# define ALGN .align 4";
		 print "#endif";

		 print "\t.section .rodata, \042a\042";
		 print "";

		 print ".globl dtrace_sdt_probes";
		 print "\tALGN";
		 print "dtrace_sdt_probes:";
	     } else {
		 print "#include <linux/sdt.h>";
	     }

	     probec = 0;
	 }

	 $2 ~ /^[tT]$/ {
	     fun = $3;

	     if (fun in probes) {
		 baseaddr = $1;
		 sub(/^0+/, "", baseaddr);

		 $0 = probes[fun];

		 for (i = 1; i <= NF; i++) {
		     prb = $i;
		     pn = fun":"prb;
		     ad = addl(baseaddr, poffst[pn]);

		     if (lfn != "kmod") {
			 print "\tPTR\t0x" ad;
			 print "\tPTR\t" length(prb);
			 print "\tPTR\t" length(fun);
			 print "\t.asciz\t\042" prb "\042";
			 print "\t.asciz\t\042" fun "\042";
			 print "\tALGN";
		     } else {
			 if (probec == 0)
			     print "static sdt_probedesc_t\t_sdt_probes[] = {";

			 print "  {\042" prb "\042, \042"fun"\042, 0x" ad " },";
		     }

		     probec++;
		 }
	     }

	     next;
	 }

	 $3 == "F" {
	     fun = $4;
	     addr = $2;

	     sub(/^0+/, "", addr);

	     next;
	 }

	 $3 == "R" {
	     sub(/^0+/, "", $2);
	     pn = fun":"$4;

	     probes[fun] = $4 " " probes[fun];
	     poffst[pn] = subl($2, addr);

	     next;
	 }

	 END {
	     if (lfn != "kmod") {
		 print "";
		 print ".globl dtrace_sdt_nprobes";
		 print "\tALGN";
		 print "dtrace_sdt_nprobes:";
		 print "\tPTR\t" probec;
	     } else {
		 if (probec > 0)
		     print "};";
		 else
		     print "#define _sdt_probes\tNULL";

		 print "#define _sdt_probec\t" probec;
	     }

	     if (errc > 0) {
		 print errc " errors generating SDT probe data." > /dev/stderr;
		 exit 1;
	     }
	 }' > $tfn

exit 0
