import 'letter_a_strokes.dart';
import 'letter_b_strokes.dart';
import 'letter_c_strokes.dart';
import 'letter_e_strokes.dart';
import 'letter_d_strokes.dart';
import 'letter_f_strokes.dart';
import 'letter_g_strokes.dart';
import 'letter_h_strokes.dart';
import 'letter_i_strokes.dart';
import 'letter_j_strokes.dart';
import 'letter_k_strokes.dart';
import 'letter_l_strokes.dart';
import 'letter_m_strokes.dart';
import 'letter_n_strokes.dart';
import 'letter_o_strokes.dart';
import 'letter_p_strokes.dart';
import 'letter_q_strokes.dart';
import 'letter_r_strokes.dart';
import 'letter_s_strokes.dart';
import 'letter_t_strokes.dart';
import 'letter_u_strokes.dart';
import 'letter_v_strokes.dart';
import 'letter_w_strokes.dart';
import 'letter_x_strokes.dart';
import 'letter_y_strokes.dart';
import 'letter_z_strokes.dart';
import 'letter_ae_strokes.dart';
import 'letter_oe_strokes.dart';
import 'letter_aa_strokes.dart';
import '../models/letter.dart';

/// Offline repository of letters with stroke paths.
/// Paths are normalized (0–100) and scaled to canvas.
class LettersRepository {
  LettersRepository._();
  static final LettersRepository _instance = LettersRepository._();
  static LettersRepository get instance => _instance;

  /// Loads all letters. A through N use SVG assets.
  Future<List<Letter>> loadLetters() async {
    final letterA = await loadLetterA();
    final letterB = await loadLetterB();
    final letterC = await loadLetterC();
    final letterD = await loadLetterD();
    final letterE = await loadLetterE();
    final letterF = await loadLetterF();
    final letterG = await loadLetterG();
    final letterH = await loadLetterH();
    final letterI = await loadLetterI();
    final letterJ = await loadLetterJ();
    final letterK = await loadLetterK();
    final letterL = await loadLetterL();
    final letterM = await loadLetterM();
    final letterN = await loadLetterN();
    final letterO = await loadLetterO();
    final letterP = await loadLetterP();
    final letterQ = await loadLetterQ();
    final letterR = await loadLetterR();
    final letterS = await loadLetterS();
    final letterT = await loadLetterT();
    final letterU = await loadLetterU();
    final letterV = await loadLetterV();
    final letterW = await loadLetterW();
    final letterX = await loadLetterX();
    final letterY = await loadLetterY();
    final letterZ = await loadLetterZ();
    final letterAe = await loadLetterAe();
    final letterOe = await loadLetterOe();
    final letterAa = await loadLetterAa();
    return [
      letterA,
      letterB,
      letterC,
      letterD,
      letterE,
      letterF,
      letterG,
      letterH,
      letterI,
      letterJ,
      letterK,
      letterL,
      letterM,
      letterN,
      letterO,
      letterP,
      letterQ,
      letterR,
      letterS,
      letterT,
      letterU,
      letterV,
      letterW,
      letterX,
      letterY,
      letterZ,
      letterAe,
      letterOe,
      letterAa,
    ];
  }
}
