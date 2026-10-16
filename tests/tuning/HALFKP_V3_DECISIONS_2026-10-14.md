# HalfKP v3 Decisions (2026-10-14)

Tento subor je git-trackovany backup klucovych rozhodnuti pre vetvu C.

## Perspektivy (must-keep)

- p0 = strana na tahu (STM)
- p1 = super (OPP)

Toto plati pre:
- engine prikaz halfkpdump,
- python hasher/checker,
- buduci trainer export diagnostiky.

## Index formula

Pre non-king figurku:

idx = (((own * 64 + king_rel) * 5 + type_idx) * 64 + piece_rel)

kde:
- own = 0 ak farba figury == farba perspektivy, inak 1
- type_idx: P,N,B,R,Q -> 0..4
- king_rel = king_sq (white POV) alebo king_sq xor 56 (black POV)
- piece_rel = sq (white POV) alebo sq xor 56 (black POV)

Rozsah: 0..40959

## Dump format (diff-friendly)

halfkpdump
p0 ks=<king_rel> n=<count> idx: <zoradene indexy>
p1 ks=<king_rel> n=<count> idx: <zoradene indexy>

Poznamka: dump musi volat ten isty indexovac ako inference cesta.

## Equivalence protocol

1. shared hasher v Python (single source of truth pre expected text)
2. engine halfkpdump
3. exact string diff (riadok-po-riadku)
4. sada 30-50 FEN pred trenovanim

Až po 0 mismatch ide trainer 2x256 a export v3.

## Export format v3 (byte-level, must-match trainer <-> loader)

Endian:
- little-endian pre vsetky integer polia

Header (fixed 32 B):
1. magic: u32 = 0x45554E4E ("NNUE")
2. version: u32 = 3
3. arch: u32 = 1 (HalfKP 2x256 int8)
4. flags: u32 = 0 (rezerva)
5. F: u32 = 40960
6. H: u32 = 256
7. shift_acc: u32
8. shift_out: u32

Payload order (presne v tomto poradi):
1. b1_stm: H x i16
2. b1_opp: H x i16
3. W1_stm: F x H x i8 (feature-major, contiguous H po feature)
4. W1_opp: F x H x i8 (feature-major, contiguous H po feature)
5. b2: i32
6. W2_stm: H x i16
7. W2_opp: H x i16

Inference fixed-point konvencia:
- acc_stm[j] = b1_stm[j] + sum(W1_stm[idx,j])
- acc_opp[j] = b1_opp[j] + sum(W1_opp[idx,j])
- h_stm[j] = clip(acc_stm[j] >> shift_acc, 0, 255)
- h_opp[j] = clip(acc_opp[j] >> shift_acc, 0, 255)
- eval_cp = (sum(h_stm[j]*W2_stm[j]) + sum(h_opp[j]*W2_opp[j]) + b2) >> shift_out

Poznamky ku kvantizacii:
- W1 su i8 (signed), b1/W2 su i16 (signed), b2 je i32.
- shift_acc a shift_out su sucast headeru a su povinne pouzite loaderom.

Ocakavana velkost suboru:
- header: 32 B
- b1_stm+b1_opp: 256*2*2 = 1024 B
- W1_stm+W1_opp: 40960*256*2 = 20,971,520 B
- b2: 4 B
- W2_stm+W2_opp: 256*2*2 = 1024 B
- spolu: 20,973,604 B (~20.00 MiB, ~20.97 MB)

Kompatibilitne pravidlo:
- Ak loader vidi ine (version, arch, F, H), musi vratit fail a engine fallbackne na classic eval.

## Quantizacna kalibracia (postmortem 2026-10-15)

- Kvantizacia sa nesmie nastavovat podla predpokladu, ale podla realnej distribucie trenovanych vah.
- Pred exportom je povinny audit distribucie `W1/W2/b1/b2` (absmax, percentile) a kontrola vyuzitia cieloveho integer rozsahu.
- Red flag: `W1_absmax_q` blizko 0/1 pri i8 rozsahu znamena kolaps signalu po exporte.
- Faza 2 MUST-HAVE: trainer-vs-loader/engine konzistencia na tych istych vahach pred akymkolvek SPRT.
