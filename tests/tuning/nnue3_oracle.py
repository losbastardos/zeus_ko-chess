#!/usr/bin/env python3
"""nnue3_oracle.py — python oracle pre NNUE v3 (HalfKP) formát.

Zrkadli engine cestu src/nnue.asm::nnue3_load + nnue3_eval v cistom
integrovanom aritmetike (i8 W1 riadky, i16 b1/W2, i32 acc, sar = floor).
Feature indexing je zhodny s halfkp_features.py (overene 1:1 oproti
engine dumpu v halfkp_equivalence_check).

Format (nnue_train3_halfkp.export_v3):
  header 8x u32 [magic, ver=3, arch, flags, F=40960, H, shift_acc, shift_out]
  b1s[H] i16, b1o[H] i16, W1s[F*H] i8, W1o[F*H] i8, b2 i32, W2s[H] i16, W2o[H] i16
  velkost = 36 + 8H + 2*F*H

Pouzitie v testoch:
  from nnue3_oracle import NNUE3
  net = NNUE3("net3.nnue")
  net.eval_stm(chess.Board(fen))
"""

import struct

import chess

PIECE_TO_IDX = {
    chess.PAWN: 0,
    chess.KNIGHT: 1,
    chess.BISHOP: 2,
    chess.ROOK: 3,
    chess.QUEEN: 4,
}


class NNUE3:
    def __init__(self, path):
        with open(path, "rb") as f:
            blob = f.read()
        magic, ver, _arch, _flags, F, H, sa, so = struct.unpack_from(
            "<8I", blob, 0)
        assert magic == 0x45554E4E, "zl magic (nie NNUE subor)"
        assert ver == 3, f"ocakavana verzia 3, je {ver}"
        assert F == 40960, f"ocakavane F=40960, je {F}"
        self.H = H
        self.shift_acc = sa
        self.shift_out = so
        off = 32
        self.b1s = list(struct.unpack_from(f"<{H}h", blob, off))
        off += 2 * H
        self.b1o = list(struct.unpack_from(f"<{H}h", blob, off))
        off += 2 * H
        n = F * H
        self.W1s = struct.unpack_from(f"<{n}b", blob, off)
        off += n
        self.W1o = struct.unpack_from(f"<{n}b", blob, off)
        off += n
        (self.b2,) = struct.unpack_from("<i", blob, off)
        off += 4
        self.W2s = list(struct.unpack_from(f"<{H}h", blob, off))
        off += 2 * H
        self.W2o = list(struct.unpack_from(f"<{H}h", blob, off))
        expected = 36 + 8 * H + 2 * F * H
        assert len(blob) == expected, f"velkost {len(blob)} != {expected}"

    def _features(self, board, persp):
        """HalfKP idx pre perspektivu (0 biela / 1 cierna), zhodne s
        halfkp_features.py aj nnue2_halfkp_idx v engine."""
        kcolor = chess.WHITE if persp == 0 else chess.BLACK
        ksq = board.king(kcolor)
        if ksq is None:
            return []
        king_rel = ksq if persp == 0 else (ksq ^ 56)
        out = []
        for sq, piece in board.piece_map().items():
            if piece.piece_type == chess.KING:
                continue
            t = PIECE_TO_IDX[piece.piece_type]
            own = 0 if piece.color == kcolor else 1
            rel = sq if persp == 0 else (sq ^ 56)
            out.append(((own * 64 + king_rel) * 5 + t) * 64 + rel)
        return out

    def eval_stm(self, board):
        """Skore z pohladu strany na tahu — rovnaky kontrakt ako
        engine nnue3_eval (evaluate neguje pre cierneho)."""
        stm = 0 if board.turn == chess.WHITE else 1
        H = self.H
        sa = self.shift_acc
        total = self.b2
        for persp, b1, W1, W2 in (
                (stm, self.b1s, self.W1s, self.W2s),
                (1 - stm, self.b1o, self.W1o, self.W2o)):
            acc = list(b1)
            for idx in self._features(board, persp):
                row = idx * H
                for j in range(H):
                    acc[j] += W1[row + j]
            for j in range(H):
                v = acc[j] >> sa
                if v < 0:
                    v = 0
                elif v > 255:
                    v = 255
                total += v * W2[j]
        return total >> self.shift_out
