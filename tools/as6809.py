#!/usr/bin/env python3
"""A small Motorola 6809 macro assembler.

usage: as6809.py main.asm -o out.bin [-l out.lst] [-s out.sym] [-D NAME=VALUE]

Source syntax
  label  op operands   ; comment      A label starts in column 1 (a trailing ':' is optional).
  .name                               A local label, scoped to the previous global label.
  NAME equ expr / NAME = expr         `=` may be reassigned, `equ` may not.

Numbers: $ff %1010 255 'c'. `*` is the current address.
Operators: + - * / % & | ^ << >> ~ ! == != < <= > >= && || ( )  and functions hi(x) lo(x).

Directives: org setdp fcb fdb fcc rmb zmb align include incbin equ assert error
            if/else/endif, ifdef/ifndef, macro/endm, offset/endo, list/nolist
  offset N ... endo    defines labels by counting rmb without emitting (structure layouts).
  bank N               code that follows lives in ROM bank N, at logical 0000-3FFF and physical
                       $10000 + N * $4000. `endbank` returns to the fixed address space.
  macro: `NAME macro a,b` ... `endm`; \\a substitutes a parameter, \\@ a unique number per expansion.

Force operand size with `<` (direct or 8-bit) and `>` (extended or 16-bit), as in lda <var or
ldx >table,y. Without them the assembler picks the shortest form that the symbols allow.
Writes the assembled image; bytes never written stay $FF.
"""
import argparse
import os
import re
import sys

REG16 = {"X": 0, "Y": 1, "U": 2, "S": 3}
TFR = {"D": 0, "X": 1, "Y": 2, "U": 3, "S": 4, "PC": 5, "A": 8, "B": 9, "CC": 10, "DP": 11, "DPR": 11, "CCR": 10}
STACK_S = {"CC": 1, "CCR": 1, "A": 2, "B": 4, "D": 6, "DP": 8, "DPR": 8, "X": 16, "Y": 32, "U": 64, "PC": 128}
STACK_U = dict(STACK_S)
del STACK_U["U"]
STACK_U["S"] = 64

INHERENT = {
    "ABX": [0x3A], "ASLA": [0x48], "ASLB": [0x58], "ASRA": [0x47], "ASRB": [0x57], "CLRA": [0x4F], "CLRB": [0x5F],
    "COMA": [0x43], "COMB": [0x53], "DAA": [0x19], "DECA": [0x4A], "DECB": [0x5A], "INCA": [0x4C], "INCB": [0x5C],
    "LSLA": [0x48], "LSLB": [0x58], "LSRA": [0x44], "LSRB": [0x54], "MUL": [0x3D], "NEGA": [0x40], "NEGB": [0x50],
    "NOP": [0x12], "ROLA": [0x49], "ROLB": [0x59], "RORA": [0x46], "RORB": [0x56], "RTI": [0x3B], "RTS": [0x39],
    "SEX": [0x1D], "SWI": [0x3F], "SWI2": [0x10, 0x3F], "SWI3": [0x11, 0x3F], "SYNC": [0x13], "TSTA": [0x4D], "TSTB": [0x5D],
}
# name: (prefix, immediate opcode or None, direct, indexed, extended, immediate size)
MEM = {}


def _mem(name, base, imm16=False, prefix=None, noimm=False):
    MEM[name] = (prefix, None if noimm else base, base + 0x10, base + 0x20, base + 0x30, 2 if imm16 else 1)


for _n, _o in {"SUBA": 0x80, "CMPA": 0x81, "SBCA": 0x82, "ANDA": 0x84, "BITA": 0x85, "LDA": 0x86, "EORA": 0x88,
               "ADCA": 0x89, "ORA": 0x8A, "ADDA": 0x8B, "SUBB": 0xC0, "CMPB": 0xC1, "SBCB": 0xC2, "ANDB": 0xC4,
               "BITB": 0xC5, "LDB": 0xC6, "EORB": 0xC8, "ADCB": 0xC9, "ORB": 0xCA, "ADDB": 0xCB}.items():
    _mem(_n, _o)
for _n, _o in {"SUBD": 0x83, "CMPX": 0x8C, "LDX": 0x8E, "ADDD": 0xC3, "LDD": 0xCC, "LDU": 0xCE}.items():
    _mem(_n, _o, imm16=True)
for _n, _o in {"STA": 0x87, "STX": 0x8F, "STB": 0xC7, "STD": 0xCD, "STU": 0xCF, "JSR": 0x8D}.items():
    _mem(_n, _o, noimm=True)
for _n, _o in {"CMPD": 0x83, "CMPY": 0x8C, "LDY": 0x8E, "LDS": 0xCE}.items():
    _mem(_n, _o, imm16=True, prefix=0x10)
for _n, _o in {"STY": 0x8F, "STS": 0xCF}.items():
    _mem(_n, _o, noimm=True, prefix=0x10)
for _n, _o in {"CMPU": 0x83, "CMPS": 0x8C}.items():
    _mem(_n, _o, imm16=True, prefix=0x11)
# Read-modify-write and jumps: direct $0x, indexed $6x, extended $7x.
RMW = {"NEG": 0x0, "COM": 0x3, "LSR": 0x4, "ROR": 0x6, "ASR": 0x7, "ASL": 0x8, "LSL": 0x8, "ROL": 0x9, "DEC": 0xA,
       "INC": 0xC, "TST": 0xD, "JMP": 0xE, "CLR": 0xF}
LEA = {"LEAX": 0x30, "LEAY": 0x31, "LEAS": 0x32, "LEAU": 0x33}
BRANCH = {"BRA": 0x20, "BRN": 0x21, "BHI": 0x22, "BLS": 0x23, "BCC": 0x24, "BHS": 0x24, "BCS": 0x25, "BLO": 0x25,
          "BNE": 0x26, "BEQ": 0x27, "BVC": 0x28, "BVS": 0x29, "BPL": 0x2A, "BMI": 0x2B, "BGE": 0x2C, "BLT": 0x2D,
          "BGT": 0x2E, "BLE": 0x2F, "BSR": 0x8D}
LONG_BRANCH = {"LBRA": [0x16], "LBSR": [0x17]}
for _n, _o in BRANCH.items():
    if _n not in ("BRA", "BSR"):
        LONG_BRANCH["L" + _n] = [0x10, _o]


class AsmError(Exception):
    pass


TOKEN = re.compile(r"\s*(\$[0-9A-Fa-f]+|%[01]+|\d+|'(?:\\.|.)'?|[A-Za-z_.@][A-Za-z0-9_.@$]*|<<|>>|==|!=|<=|>=|&&|\|\||[-+*/%&|^~!()<>,])")


class Expr:
    """Recursive-descent expression evaluator. Raises KeyError for an unresolved symbol."""

    PRECEDENCE = [["||"], ["&&"], ["|"], ["^"], ["&"], ["==", "!="], ["<", "<=", ">", ">="], ["<<", ">>"], ["+", "-"], ["*", "/", "%"]]

    def __init__(self, asm, text):
        self.asm = asm
        self.tokens = []
        pos = 0
        while pos < len(text):
            if text[pos:].strip() == "":
                break
            m = TOKEN.match(text, pos)
            if not m:
                raise AsmError(f"bad expression near '{text[pos:]}'")
            self.tokens.append(m.group(1))
            pos = m.end()
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else None

    def next(self):
        t = self.peek()
        self.i += 1
        return t

    def evaluate(self):
        v = self.binary(0)
        if self.peek() is not None:
            raise AsmError(f"unexpected '{self.peek()}' in expression")
        return v

    def binary(self, level):
        if level == len(self.PRECEDENCE):
            return self.unary()
        v = self.binary(level + 1)
        while self.peek() in self.PRECEDENCE[level]:
            op = self.next()
            r = self.binary(level + 1)
            if op == "+": v += r
            elif op == "-": v -= r
            elif op == "*": v *= r
            elif op == "/":
                if r == 0:
                    raise AsmError("division by zero")
                v = int(v / r)
            elif op == "%":
                if r == 0:
                    raise AsmError("division by zero")
                v = v - r * int(v / r)
            elif op == "&": v &= r
            elif op == "|": v |= r
            elif op == "^": v ^= r
            elif op == "<<": v <<= r
            elif op == ">>": v >>= r
            elif op == "==": v = int(v == r)
            elif op == "!=": v = int(v != r)
            elif op == "<": v = int(v < r)
            elif op == "<=": v = int(v <= r)
            elif op == ">": v = int(v > r)
            elif op == ">=": v = int(v >= r)
            elif op == "&&": v = int(bool(v) and bool(r))
            elif op == "||": v = int(bool(v) or bool(r))
        return v

    def unary(self):
        t = self.next()
        if t is None:
            raise AsmError("expression ended early")
        if t == "-":
            return -self.unary()
        if t == "+":
            return self.unary()
        if t == "~":
            return ~self.unary()
        if t == "!":
            return int(not self.unary())
        if t == "*":
            return self.asm.pc
        if t == "(":
            v = self.binary(0)
            if self.next() != ")":
                raise AsmError("missing )")
            return v
        if t[0] == "$":
            return int(t[1:], 16)
        if t[0] == "%":
            return int(t[1:], 2)
        if t[0].isdigit():
            return int(t)
        if t[0] == "'":
            body = t[1:].rstrip("'") if len(t) > 2 else t[1:]
            return ord({"\\n": "\n", "\\t": "\t", "\\0": "\0", "\\\\": "\\", "\\'": "'"}.get(body, body))
        low = t.lower()
        if low == "bank" and self.peek() == "(":
            self.next()
            name = self.next()
            if self.next() != ")":
                raise AsmError("missing )")
            key = self.asm.qualify(name).upper()
            try:
                self.asm.lookup(name)
            except KeyError:
                if self.asm.stub_undefined and "UNDEF_STUB" in self.asm.previous:
                    self.asm.missing.add(name.upper())
                    return 0
                raise
            return self.asm.label_bank.get(key, 0)
        if low in ("hi", "lo") and self.peek() == "(":
            self.next()
            v = self.binary(0)
            if self.next() != ")":
                raise AsmError("missing )")
            return (v >> 8) & 0xFF if low == "hi" else v & 0xFF
        return self.asm.lookup(t)


def strip_comment(line):
    in_str = None
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == in_str:
                in_str = None
        elif c == '"':
            in_str = c
        elif c == "'" and i + 2 < len(line) + 1 and i + 2 <= len(line) - 1 and line[i + 2] == "'":
            i += 2
        elif c == "'" and i + 1 < len(line):
            i += 1  # 'c style character without a closing quote
        elif c == ";":
            return line[:i]
        i += 1
    return line


def split_operands(text):
    """Split on commas outside strings, parentheses and brackets."""
    parts, cur, depth, in_str = [], "", 0, False
    for c in text:
        if c == '"':
            in_str = not in_str
        if not in_str:
            if c in "([":
                depth += 1
            elif c in ")]":
                depth -= 1
            elif c == "," and depth == 0:
                parts.append(cur.strip())
                cur = ""
                continue
        cur += c
    parts.append(cur.strip())
    return parts


class Assembler:
    def __init__(self, defines=None, stub_undefined=False):
        self.defines = defines or {}
        self.stub_undefined = stub_undefined
        self.missing = set()
        self.symbols = {}
        self.previous = {}
        self.final = False
        self.macros = {}
        self.pc = 0
        self.image = {}
        self.listing = []
        self.errors = []
        self.scope = ""
        self.dp = None
        self.offset_mode = False
        self.saved_pc = 0
        self.unique = 0
        self.unresolved = False
        self.sizes = {}        # statement id -> size chosen, to keep shrinking monotonic
        self.statement = 0
        self.mutable = set()
        self.bank = None
        self.label_bank = {}
        self.banked_labels = set()

    # ---- symbols ------------------------------------------------------
    def qualify(self, name):
        return self.scope + name if name.startswith(".") else name

    def lookup(self, name):
        key = self.qualify(name).upper()
        if key in self.symbols:
            return self.symbols[key]
        if key in self.previous:
            return self.previous[key]
        raise KeyError(name)

    def define(self, name, value, mutable=False):
        key = self.qualify(name).upper()
        if key in self.symbols and not mutable and key not in self.mutable and self.symbols[key] != value:
            raise AsmError(f"symbol {name} redefined")
        if mutable:
            self.mutable.add(key)
        self.symbols[key] = value

    def value(self, text):
        """Value of an expression; on the final pass an unknown symbol is an error."""
        try:
            return Expr(self, text).evaluate()
        except KeyError as e:
            if self.stub_undefined and "UNDEF_STUB" in self.previous:
                self.missing.add(e.args[0].upper())
                return self.previous["UNDEF_STUB"]
            if self.final:
                raise AsmError(f"undefined symbol {e.args[0]}")
            self.unresolved = True
            return None

    def known(self, text):
        return self.value(text)

    # ---- output -------------------------------------------------------
    def emit(self, *data):
        for b in data:
            if not self.offset_mode:
                if self.pc > 0xFFFF:
                    raise AsmError("address past $FFFF")
                if self.bank is None:
                    phys = self.pc
                else:
                    if self.pc >= 0x4000:
                        raise AsmError(f"bank {self.bank} overflows $4000")
                    phys = 0x10000 + self.bank * 0x4000 + self.pc
                if self.final and phys in self.image:
                    raise AsmError(f"address ${phys:05X} written twice")
                self.image[phys] = b & 0xFF
            self.pc += 1

    def emit16(self, v):
        self.emit((v >> 8) & 0xFF, v & 0xFF)

    def check8(self, v, what="value"):
        if self.final and not -128 <= v <= 255:
            raise AsmError(f"{what} {v} does not fit in 8 bits")

    def check16(self, v):
        if self.final and not -32768 <= v <= 65535:
            raise AsmError(f"value {v} does not fit in 16 bits")

    # ---- operand encoders --------------------------------------------
    def choose(self, want_small):
        """Size selection keeps a statement from growing back after it shrank, so passes converge."""
        key = self.statement
        if want_small:
            self.sizes[key] = True
        return self.sizes.get(key, False)

    def indexed(self, operand):
        """Returns the postbyte and extra bytes for an indexed operand."""
        indirect = False
        s = operand.strip()
        if s.startswith("["):
            if not s.endswith("]"):
                raise AsmError("missing ]")
            indirect = True
            s = s[1:-1].strip()
        ind = 0x10 if indirect else 0
        if "," not in s:
            if not indirect:
                raise AsmError("not an indexed operand")
            v = self.value(s.lstrip(">"))
            return [0x9F], [(0 if v is None else v) >> 8 & 0xFF, (0 if v is None else v) & 0xFF]
        pos = s.rfind(",")
        off, reg = s[:pos].strip(), s[pos + 1:].strip().upper()

        m = re.fullmatch(r"(-{0,2})([XYUS])(\+{0,2})", reg)
        if m:
            pre, r, post = m.groups()
            rr = REG16[r] << 5
            if pre or post:
                if off:
                    raise AsmError("auto increment takes no offset")
                if pre and post:
                    raise AsmError("bad indexed mode")
                if indirect and (pre == "-" or post == "+"):
                    raise AsmError("single auto increment cannot be indirect")
                code = {"+": 0x80, "++": 0x81, "-": 0x82, "--": 0x83}[post or pre]
                return [code | rr | ind], []
            up = off.upper()
            if up == "A":
                return [0x86 | rr | ind], []
            if up == "B":
                return [0x85 | rr | ind], []
            if up == "D":
                return [0x8B | rr | ind], []
            force = None
            if off.startswith("<<"):
                force = 5
                off = off[2:]
            elif off.startswith("<"):
                force = 8
                off = off[1:]
            elif off.startswith(">"):
                force = 16
                off = off[1:]
            if off == "":
                return [0x84 | rr | ind], []
            v = self.value(off)
            if force == 8:
                w = 0 if v is None else v
                self.check8(w, "offset")
                return [0x88 | rr | ind], [w & 0xFF]
            if force == 16 or v is None:
                if v is None and force is None:
                    # Unknown this pass: reserve the largest form.
                    return [0x89 | rr | ind], [0, 0]
                w = 0 if v is None else v
                return [0x89 | rr | ind], [(w >> 8) & 0xFF, w & 0xFF]
            if v == 0 and not force:
                return [0x84 | rr | ind], []
            if -16 <= v <= 15 and not indirect:
                return [(rr | (v & 0x1F))], []
            if -128 <= v <= 127:
                return [0x88 | rr | ind], [v & 0xFF]
            return [0x89 | rr | ind], [(v >> 8) & 0xFF, v & 0xFF]
        if reg in ("PC", "PCR"):
            force = None
            if off.startswith("<"):
                force = 8
                off = off[1:]
            elif off.startswith(">"):
                force = 16
                off = off[1:]
            v = self.value(off)
            if v is None:
                return [0x8D | ind], [0, 0]
            # PCR computes the distance from the instruction's end. `pcr_base` is the address of
            # the postbyte, set by the caller.
            d8 = v - (self.pcr_base + 2)
            if force == 8 or (force is None and -128 <= d8 <= 127 and self.choose(True)):
                if self.final and not -128 <= d8 <= 127:
                    raise AsmError("PCR offset out of 8-bit range")
                return [0x8C | ind], [d8 & 0xFF]
            d16 = v - (self.pcr_base + 3)
            return [0x8D | ind], [(d16 >> 8) & 0xFF, d16 & 0xFF]
        raise AsmError(f"bad index register '{reg}'")

    def memory(self, prefix, imm, direct, idx, ext, immsize, operand, name):
        pre = [prefix] if prefix else []
        s = operand.strip()
        if s.startswith("#"):
            if imm is None:
                raise AsmError(f"{name} has no immediate mode")
            v = self.value(s[1:])
            v = 0 if v is None else v
            self.emit(*pre, imm)
            if immsize == 1:
                self.check8(v, "immediate")
                self.emit(v & 0xFF)
            else:
                self.check16(v)
                self.emit16(v & 0xFFFF)
            return
        if s.startswith("[") or "," in s:
            self.pcr_base = self.pc + len(pre) + 1
            post, extra = self.indexed(s)
            self.emit(*pre, idx, *post, *extra)
            return
        force = None
        if s.startswith("<"):
            force = "d"
            s = s[1:]
        elif s.startswith(">"):
            force = "e"
            s = s[1:]
        v = self.value(s)
        if force == "d":
            w = 0 if v is None else v
            if self.final and self.dp is not None and (w >> 8) & 0xFF != self.dp:
                raise AsmError(f"${w:04X} is not in direct page ${self.dp:02X}")
            self.emit(*pre, direct, w & 0xFF)
            return
        if force is None and v is not None and self.dp is not None and (v >> 8) & 0xFF == self.dp and 0 <= v <= 0xFFFF:
            self.emit(*pre, direct, v & 0xFF)
            return
        w = 0 if v is None else v
        self.check16(w)
        self.emit(*pre, ext)
        self.emit16(w & 0xFFFF)

    def check_bank(self, op, operand):
        """A direct call or jump into a different ROM bank would run whatever is mapped there."""
        target = operand.strip().lstrip("<>")
        if not re.fullmatch(r"\.?[A-Za-z_@][A-Za-z0-9_.@$]*", target):
            return
        key = self.qualify(target).upper()
        if key in self.banked_labels and self.label_bank[key] != self.bank:
            raise AsmError(f"{op} to {target} crosses into bank {self.label_bank[key]}: use FAR")

    def instruction(self, op, operand):
        if self.final and op in ("JSR", "JMP", "BSR", "BRA", "LBRA", "LBSR"):
            self.check_bank(op, operand)
        if op in INHERENT:
            self.emit(*INHERENT[op])
        elif op in MEM:
            p, i, d, x, e, sz = MEM[op]
            self.memory(p, i, d, x, e, sz, operand, op)
        elif op in RMW:
            n = RMW[op]
            self.memory(None, None, n, 0x60 + n, 0x70 + n, 1, operand, op)
        elif op in LEA:
            self.pcr_base = self.pc + 1
            post, extra = self.indexed(operand)
            self.emit(LEA[op], *post, *extra)
        elif op in BRANCH:
            v = self.value(operand)
            self.emit(BRANCH[op])
            d = 0 if v is None else v - (self.pc + 1)
            if self.final and not -128 <= d <= 127:
                raise AsmError(f"branch out of range ({d})")
            self.emit(d & 0xFF)
        elif op in LONG_BRANCH:
            v = self.value(operand)
            self.emit(*LONG_BRANCH[op])
            d = 0 if v is None else v - (self.pc + 2)
            self.emit16(d & 0xFFFF)
        elif op in ("TFR", "EXG"):
            parts = split_operands(operand)
            if len(parts) != 2 or parts[0].upper() not in TFR or parts[1].upper() not in TFR:
                raise AsmError(f"bad {op} registers")
            a, b = TFR[parts[0].upper()], TFR[parts[1].upper()]
            if (a >= 8) != (b >= 8):
                raise AsmError(f"{op} between 8 and 16 bit registers")
            self.emit(0x1F if op == "TFR" else 0x1E, a << 4 | b)
        elif op in ("PSHS", "PULS", "PSHU", "PULU"):
            table = STACK_U if op.endswith("U") else STACK_S
            mask = 0
            for r in split_operands(operand):
                if r.upper() not in table:
                    raise AsmError(f"bad register {r} for {op}")
                mask |= table[r.upper()]
            self.emit({"PSHS": 0x34, "PULS": 0x35, "PSHU": 0x36, "PULU": 0x37}[op], mask)
        elif op in ("ANDCC", "ORCC", "CWAI"):
            s = operand.strip()
            if not s.startswith("#"):
                raise AsmError(f"{op} needs an immediate")
            v = self.value(s[1:])
            self.emit({"ANDCC": 0x1C, "ORCC": 0x1A, "CWAI": 0x3C}[op], 0 if v is None else v & 0xFF)
        else:
            raise AsmError(f"unknown instruction {op}")

    # ---- directives ---------------------------------------------------
    def data(self, operand, wide):
        for part in split_operands(operand):
            if part.startswith('"'):
                if wide:
                    raise AsmError("string in fdb")
                self.emit(*[ord(c) for c in part.strip('"')])
                continue
            v = self.value(part)
            v = 0 if v is None else v
            if wide:
                self.check16(v)
                self.emit16(v & 0xFFFF)
            else:
                self.check8(v)
                self.emit(v & 0xFF)

    def required(self, text):
        v = self.value(text)
        if v is None:
            raise AsmError(f"'{text}' must be known on the first pass")
        return v

    def run_lines(self, lines, filename):
        """Assemble a list of source lines, tracking conditionals and macro definitions."""
        cond = []  # stack of [active, taken]
        macro_name = None
        macro_body = None
        macro_params = None
        macro_depth = 0
        for number, raw in enumerate(lines, 1):
            line = strip_comment(raw.rstrip())
            self.where = f"{filename}:{number}"
            try:
                m = re.match(r"^([A-Za-z_.@][A-Za-z0-9_.@$]*)?:?\s*(.*)$", line) if line[:1] not in (" ", "\t", "") else None
                label = m.group(1) if m else None
                rest = (m.group(2) if m else line).strip()
                parts = rest.split(None, 1)
                op = parts[0].upper() if parts else ""
                operand = parts[1].strip() if len(parts) > 1 else ""

                if macro_name is not None:
                    if op == "MACRO":
                        macro_depth += 1
                    if op == "ENDM":
                        if macro_depth == 0:
                            self.macros[macro_name] = (macro_params, macro_body)
                            macro_name = None
                            continue
                        macro_depth -= 1
                    macro_body.append(raw)
                    continue

                if op in ("IF", "IFDEF", "IFNDEF"):
                    active = all(c[0] for c in cond)
                    taken = False
                    if active:
                        if op == "IF":
                            taken = bool(self.required(operand))
                        else:
                            taken = (operand.upper() in self.symbols or operand.upper() in self.defines) == (op == "IFDEF")
                    cond.append([active and taken, taken, active])
                    continue
                if op == "ELSE":
                    if not cond:
                        raise AsmError("else without if")
                    c = cond[-1]
                    c[0] = c[2] and not c[1]
                    continue
                if op == "ENDIF":
                    if not cond:
                        raise AsmError("endif without if")
                    cond.pop()
                    continue
                if not all(c[0] for c in cond):
                    continue

                if op == "MACRO":
                    if not label:
                        raise AsmError("macro needs a name")
                    macro_name = label.upper()
                    macro_params = [p.strip() for p in operand.split(",")] if operand else []
                    macro_body = []
                    macro_depth = 0
                    continue

                if op in ("EQU", "="):
                    if not label:
                        raise AsmError("equ needs a label")
                    v = self.value(operand)
                    if v is not None:
                        self.define(label, v, mutable=op == "=")
                    continue
                if rest.startswith("=") and label:
                    v = self.value(rest[1:])
                    if v is not None:
                        self.define(label, v, mutable=True)
                    continue

                if label:
                    if not label.startswith("."):
                        self.scope = label.upper()
                    self.define(label, self.pc)
                    key = self.qualify(label).upper()
                    if self.bank is not None and not self.offset_mode:
                        self.label_bank[key] = self.bank
                        self.banked_labels.add(key)
                if not op:
                    continue

                start = self.pc
                self.statement += 1
                if op in self.macros:
                    self.expand(op, operand)
                    continue
                if op == "ORG":
                    self.pc = self.required(operand)
                elif op == "BANK":
                    self.bank = self.required(operand)
                    if not 0 <= self.bank <= 11:
                        raise AsmError("bank must be 0-11: the board's ROM list has 12 banks")
                elif op == "ENDBANK":
                    self.bank = None
                elif op == "SETDP":
                    self.dp = None if operand.strip() == "" else self.required(operand) & 0xFF
                elif op in ("FCB", "DB", "BYTE"):
                    self.data(operand, False)
                elif op in ("FDB", "DW", "WORD"):
                    self.data(operand, True)
                elif op == "FCC":
                    self.data(operand, False)
                elif op == "RMB":
                    self.pc += self.required(operand)
                elif op == "ZMB":
                    self.emit(*([0] * self.required(operand)))
                elif op == "ALIGN":
                    n = self.required(operand)
                    while self.pc % n:
                        self.emit(0xFF)
                elif op == "OFFSET":
                    self.saved_pc = self.pc
                    self.offset_mode = True
                    self.pc = self.required(operand) if operand else 0
                elif op == "ENDO":
                    self.offset_mode = False
                    self.pc = self.saved_pc
                elif op == "INCLUDE":
                    self.include(operand.strip().strip('"'), filename)
                elif op == "INCBIN":
                    path = os.path.join(os.path.dirname(filename), operand.strip().strip('"'))
                    with open(path, "rb") as f:
                        self.emit(*f.read())
                elif op == "ASSERT":
                    bits = split_operands(operand)
                    v = self.value(bits[0])
                    if self.final and not v:
                        raise AsmError("assert failed: " + (bits[1].strip('"') if len(bits) > 1 else bits[0]))
                elif op == "ERROR":
                    raise AsmError(operand.strip('"'))
                elif op in ("LIST", "NOLIST", "END"):
                    pass
                else:
                    self.instruction(op, operand)
                if self.final and self.pc != start and not self.offset_mode and op not in ("ORG", "RMB"):
                    base = 0 if self.bank is None else 0x10000 + self.bank * 0x4000
                    code = " ".join(f"{self.image.get(base + a, 0):02X}" for a in range(start, min(self.pc, start + 8)))
                    self.listing.append(f"{start:04X}  {code:<24} {raw.rstrip()}")
                elif self.final:
                    self.listing.append(f"{'':<30} {raw.rstrip()}")
            except AsmError as e:
                self.errors.append(f"{self.where}: {e}")
                if len(self.errors) > 40:
                    raise SystemExit("\n".join(self.errors))
        if cond:
            self.errors.append(f"{filename}: missing endif")
        if macro_name:
            self.errors.append(f"{filename}: missing endm for {macro_name}")

    def expand(self, name, operand):
        params, body = self.macros[name]
        args = split_operands(operand) if operand else []
        if len(args) != len(params):
            raise AsmError(f"macro {name} takes {len(params)} arguments, got {len(args)}")
        self.unique += 1
        out = []
        for line in body:
            for p, a in sorted(zip(params, args), key=lambda t: -len(t[0])):
                line = line.replace("\\" + p, a)
            out.append(line.replace("\\@", str(self.unique)))
        where = self.where
        scope = self.scope
        self.run_lines(out, f"{where} ({name})")
        self.scope = scope
        self.where = where

    def include(self, name, current):
        path = os.path.join(os.path.dirname(current), name)
        try:
            with open(path, encoding="utf8") as f:
                lines = f.read().splitlines()
        except OSError as e:
            raise AsmError(f"cannot include {name}: {e.strerror}")
        self.run_lines(lines, path)

    # ---- passes -------------------------------------------------------
    def assemble(self, path, max_passes=30):
        with open(path, encoding="utf8") as f:
            lines = f.read().splitlines()
        for pass_number in range(max_passes):
            self.pc = 0
            self.unique = 0
            self.bank = None
            self.scope = ""
            self.dp = None
            self.image = {}
            self.errors = []
            self.unresolved = False
            self.statement = 0
            self.previous = self.symbols
            self.symbols = {}
            self.mutable = set()
            for k, v in self.defines.items():
                self.symbols[k.upper()] = v
            self.macros = {}
            self.run_lines(lines, path)
            stable = not self.unresolved and self.symbols == self.previous
            if stable and not self.errors:
                break
            if pass_number > 2 and self.errors and not self.unresolved and self.symbols == self.previous:
                break
        else:
            self.errors.append("symbol values did not settle")
        # A last pass with strict checks, which also builds the listing.
        self.final = True
        self.previous = self.symbols
        self.symbols = {}
        self.pc = 0
        self.unique = 0
        self.bank = None
        self.scope = ""
        self.dp = None
        self.image = {}
        self.errors = []
        self.statement = 0
        self.mutable = set()
        for k, v in self.defines.items():
            self.symbols[k.upper()] = v
        self.macros = {}
        self.listing = []
        self.run_lines(lines, path)
        if self.symbols != self.previous:
            self.errors.append("final pass disagreed with the previous pass")
        return not self.errors


def main():
    ap = argparse.ArgumentParser(description="6809 assembler")
    ap.add_argument("source")
    ap.add_argument("-o", "--output", required=True, help="64K image file")
    ap.add_argument("-l", "--listing")
    ap.add_argument("-s", "--symbols")
    ap.add_argument("-D", "--define", action="append", default=[])
    ap.add_argument("--banked", action="store_true", help="always write the full $50000 Blaster image")
    ap.add_argument("--stub-undefined", action="store_true", help="resolve undefined symbols to UNDEF_STUB and list them")
    args = ap.parse_args()
    defines = {}
    for d in args.define:
        name, _, value = d.partition("=")
        defines[name] = int(value, 0) if value else 1
    asm = Assembler(defines, args.stub_undefined)
    if not asm.assemble(args.source):
        print("\n".join(asm.errors), file=sys.stderr)
        return 1
    image = bytearray(b"\xff" * (0x50000 if max(asm.image, default=0) > 0xFFFF or args.banked else 0x10000))
    for address, byte in asm.image.items():
        image[address] = byte
    with open(args.output, "wb") as f:
        f.write(image)
    if args.listing:
        with open(args.listing, "w", encoding="utf8") as f:
            f.write("\n".join(asm.listing) + "\n")
    if args.symbols:
        with open(args.symbols, "w", encoding="utf8") as f:
            for name, value in sorted(asm.symbols.items(), key=lambda kv: (kv[1], kv[0])):
                f.write(f"{value & 0xFFFF:04X} {name}\n")
    print(f"assembled {len(asm.image)} bytes, {len(asm.symbols)} symbols")
    if args.stub_undefined:
        print(f"missing symbols: {len(asm.missing)}")
        if asm.missing:
            print("  " + " ".join(sorted(asm.missing)))
    regions = [("fixed 4000-8FFF", 0x4000, 0x9000), ("fixed D000-FFFF", 0xD000, 0x10000)]
    regions += [(f"bank {b}", 0x10000 + b * 0x4000, 0x14000 + b * 0x4000) for b in range(16)]
    for name, lo, hi in regions:
        used = sum(1 for a in asm.image if lo <= a < hi)
        if used:
            print(f"  {name:16} {used:6} / {hi - lo}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
