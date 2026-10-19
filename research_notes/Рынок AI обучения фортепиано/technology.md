# Technology landscape: "any song → playable piano tutorial that listens to you play" (as of Oct 2026)

Scope note: research done 2026-10-19. Licenses below were read directly from the repos' LICENSE files on GitHub (raw.githubusercontent.com) where a URL to the LICENSE file is given. Benchmark numbers are as reported by the papers' authors unless noted. Where a source is a third-party aggregator or vendor marketing, that is flagged.

## 1. Automatic music transcription (AMT): state of the art, licenses, accuracy, runtime, on-device

### Takeaway
Solo-piano audio→MIDI is essentially a solved, commoditized problem: several permissively licensed models (Transkun v2 MIT, hFT-Transformer MIT, Kong/ByteDance Apache-2.0, Aria-AMT Apache-2.0) reach 97–98% note-onset F1 on MAESTRO and run in seconds per song on a cheap GPU. Multi-instrument transcription (MT3 family, YourMT3+, new open MuScriptor 2026) is much weaker (~74–84% F1 on synthetic Slakh, worse on real recordings) and some of the best code is copyleft (YourMT3 is GPL-3.0), so it is not where a moat can come from either.

### Cited Findings

**Solo piano models (MAESTRO v3 test set, F1 %)**
- Transkun v2 ("Scoring Time Intervals using Non-Hierarchical Transformer", Yan & Duan, ISMIR 2024): 12.9M params; Frame 95.35 / Note-onset 98.32 / Note+offset 93.48 / Note+offset+velocity 92.94; sustain-pedal frame F1 95.40. Training took ~6 days on 2× RTX 4090. — [arXiv 2404.09466](https://arxiv.org/html/2404.09466)
- Same table: hFT-Transformer (Sony, ISMIR 2023) 5.5M params, Frame 93.24 / Note 97.44 / Note+offset 90.53 / +velocity 89.48 (as reported by Toyama et al.); Semi-CRF v1 (Transkun v1, NeurIPS 2021) 9.8M params, Note 96.11; Kong et al. (ByteDance high-resolution) 20.2M params, sustain-pedal frame F1 94.25. — [arXiv 2404.09466](https://arxiv.org/html/2404.09466); hFT paper [arXiv 2307.04305](https://arxiv.org/abs/2307.04305)
- Transkun ships as `pip install transkun` with a one-line CLI (`transkun input.mp3 output.mid --device cuda`); shipped checkpoint is trained without pedal extension of notes and with data augmentation. — [Transkun README](https://github.com/Yujia-Yan/Transkun)
- Transkun license: MIT (Copyright 2021 Yujia Yan). — [LICENSE](https://raw.githubusercontent.com/Yujia-Yan/Transkun/main/LICENSE)
- hFT-Transformer license: MIT (Copyright 2023 Sony Group Corporation); checkpoint downloadable from GitHub releases; trained on A100, evaluated on RTX 2080 Ti. — [LICENSE](https://raw.githubusercontent.com/sony/hFT-Transformer/master/LICENSE); [README](https://github.com/sony/hFT-Transformer)
- ByteDance / Kong et al. high-resolution piano transcription: README states "LICENSE: Apache 2.0". — [bytedance/piano_transcription README](https://github.com/bytedance/piano_transcription)
- Aria-AMT (EleutherAI): "efficient and robust implementation of seq-to-seq automatic piano transcription"; Apache-2.0 license; weights described as "preliminary" (piano-medium-double-1.0); supports torch.compile and int8 quantization (int8 only on BF16-capable GPUs). — [aria-amt README](https://github.com/EleutherAI/aria-amt); [LICENSE](https://raw.githubusercontent.com/EleutherAI/aria-amt/main/LICENSE)
- Aria-AMT was built to handle diverse timbres and recording quality and was used to create the Aria-MIDI dataset (transcribing large amounts of web piano audio) (2025). — [Aria-MIDI paper arXiv 2504.15071](https://arxiv.org/html/2504.15071v1)
- A 2026 paper states neural semi-CRF event decoding (the Transkun line) "defines the current state of the art" for piano transcription, and notes that standard benchmarks extend note offsets through sustain pedal, so offset scores measure end-of-sound rather than key release. — [arXiv 2608.03419](https://arxiv.org/html/2608.03419v1)
- Evaluation caveat: standard frame/note metrics miss musical dimensions, and piano transcription models show lack of generalization across acoustic environments (2024). — [arXiv 2406.08454](https://arxiv.org/html/2406.08454v2)
- Streaming piano transcription (Wei, Zhao, Wu, Yoshii; ISMIR 2024, arXiv 2025): causal encoder-decoder with sustain pedal detection that performs "comparably with or even better than" state-of-the-art offline methods on MAESTRO and significantly reduces compute vs. offline transformers (no ms latency figures in abstract). — [arXiv 2503.01362](https://arxiv.org/abs/2503.01362)
- Onsets and Frames (Magenta, 2018): CNN+LSTM; ported to the browser with TensorFlow.js (Magenta.js v1.2); the repo is now inactive and points to MT3. — [Magenta O&F page](https://magenta.tensorflow.org/onsets-frames); [oaf-js](https://magenta.tensorflow.org/oaf-js); [GitHub](https://github.com/magenta/magenta/blob/main/magenta/models/onsets_frames_transcription)

**Multi-instrument models**
- MT3 (Google Magenta) license: Apache-2.0. — [LICENSE](https://raw.githubusercontent.com/magenta/mt3/main/LICENSE)
- MR-MT3 (Tan, Cheuk, Cho, Liao, Mitsufuji, 2024; Sony-affiliated authors): MIT license. — [LICENSE](https://raw.githubusercontent.com/gudgud96/MR-MT3/master/LICENSE)
- YourMT3 / YourMT3+ (Chang et al., MLSP 2024): GPL-3.0 license (copyleft — problematic for closed-source commercial products that distribute the code). — [LICENSE](https://raw.githubusercontent.com/mimbres/YourMT3/main/LICENSE); [README](https://github.com/mimbres/YourMT3)
- YourMT3+ (best variant YPTF.MoE+Multi, 45.8M params): MAESTRO note-onset F1 96.98 (vs. hFT-Transformer baseline 97.44, MT3 94.86); Slakh2100 non-drum onset F1 84.56, multi-instrument (onset+offset+program) F1 74.84 vs. MT3 57.16 (Colab re-eval) / 62 (MT3 authors' report). — [arXiv 2407.04822v2](https://arxiv.org/html/2407.04822v2)
- YourMT3+ runtime: ~6 min of piano audio took ~40 s fp32 / ~10 s fp16 on a free Colab T4; under 10 s on Ampere+ GPUs with 16-bit mixed precision. Trained on 2× A100. Training data: MusicNet-EM, GuitarSet, MIR-ST500, ENST-Drums, Slakh, EGMD, MAESTRO, CMedia, URMP, SMT-Bass. — [arXiv 2407.04822v2](https://arxiv.org/html/2407.04822v2)
- 2025 AMT Challenge (NeurIPS 2025 AI for Music workshop; arXiv Mar 2026): 8 teams submitted valid solutions, only 2 beat the MT3 baseline; conclusions — polyphony and timbre variation remain difficult. — [arXiv 2603.27528](https://arxiv.org/abs/2603.27528)
- The winning 2025 AMT Challenge system extended YourMT3+ with a MusicFM encoder backbone; outside the competition it reached a Slakh2100 multi-instrument F-measure of 0.83 (from search snippet of the paper). — [arXiv 2603.27528 PDF](https://arxiv.org/pdf/2603.27528)
- MuScriptor (Rouard, Krause, Roebel, Simon-Gabriel, Défossez; ISMIR 2026, July 2026): "an open-weight multi-instrument music transcription model" for real-world recordings across genres, trained with synthetic pre-training, real-audio fine-tuning and RL post-training, with instrument-presence conditioning. Weight license not stated on the abstract page. — [arXiv 2607.08168](https://arxiv.org/abs/2607.08168)
- Spotify Basic Pitch (Bittner et al., ICASSP 2022): instrument-agnostic polyphonic note + pitch-bend model with <17K parameters and <20 MB peak memory, faster than real time on most computers, runs in the browser (basicpitch.io); accuracy "comparable" to a multi-instrument AMT baseline. — [Spotify Engineering blog](https://engineering.atspotify.com/2022/06/meet-basic-pitch); License Apache-2.0 — [LICENSE](https://raw.githubusercontent.com/spotify/basic-pitch/main/LICENSE)

**Cost/compute reference**
- Modal serverless GPU list price: NVIDIA L4 ≈ $0.000222/s (~$0.80/h), A10 ≈ $0.000306/s (~$1.10/h), per 2026 snapshots of Modal's pricing page (third-party aggregator; region pinning adds 1.5–1.75×, non-preemptible 3×). — [Spheron blog on Modal pricing 2026](https://www.spheron.network/blog/modal-gpu-pricing-2026-per-second-billing/); [computeprices.com Modal L4](https://computeprices.com/providers/modal/gpus/l4)

### Inferences
- For solo piano, any of Transkun v2 / hFT / Kong / Aria-AMT is "good enough" and commercially licensable at the code level; the remaining differentiation is robustness to phone-mic recordings and home pianos, not MAESTRO F1 (which is saturated at ~97–98% onset F1).
- Note that a permissive *code* license does not settle the *weights* question: all of these piano checkpoints are trained on MAESTRO (CC BY-NC-SA 4.0, see §6). A cautious startup may need to retrain on licensed/synthetic data.
- Estimated GPU cost for transcription alone: using YourMT3+'s ~10 s GPU time per 6 min of audio and L4 at ~$0.80/h, transcription of a 4-min song is ≈ $0.001–0.003 of GPU time; even with 5–10× overhead (cold starts, separation, beat tracking, arrangement) the whole pipeline is very likely under $0.05 per song on serverless GPUs. GPU cost is not a meaningful barrier or moat.
- On-device: Basic Pitch (17K params) is clearly on-device feasible; 5–13M-param piano models (hFT 5.5M, Transkun 12.9M) are plausibly feasible on modern phones with Core ML/ONNX conversion (a third-party ONNX export of Transkun exists: [TuesdayCrowd/transkun-onnx](https://huggingface.co/TuesdayCrowd/transkun-onnx)), but I found no published phone benchmark.

### Gaps
- Exact Kong et al. (2020/2021) MAESTRO note F1 not verified from the primary paper in this session (a 2026 paper summary says ">0.97" joint onset-pitch F1, unverified).
- MuScriptor benchmark numbers and weight license were not available from the abstract page.
- Aria-AMT accuracy on MAESTRO not found.
- No published mobile latency / real-time-factor benchmarks for hFT, Transkun or Aria-AMT on phones.
- The Transkun ONNX page claims 0.984 MAESTRO note F1 (third-party, consistent with the 98.32 in the paper).

## 2. The hard problem: full band/pop mix → playable piano ARRANGEMENT

### Takeaway
"Transcribe a pop song" is not a transcription problem but a generation/arrangement problem; the research frontier (Pop2Piano 2023 → PiCoGen/PiCoGen2 2024 → AMT-APC 2024 → Etude 2025/26) has moved from direct audio→piano tokens to staged pipelines (feature extraction + beat grid + symbolic decoder). The best 2025–26 system (Etude) still scores clearly below human arrangers (3.50 vs 3.92 overall on a 5-point scale), none offers true difficulty levels, and the enabling training data (pop song ↔ YouTube piano cover pairs) is legally grey. This is the most likely technical moat area.

### Cited Findings

**Source separation (stem extraction)**
- Demucs v4 / HTDemucs (Meta): MIT license; repo no longer maintained by Meta (author moved to a fork, "only important bug fixes"). — [demucs README](https://github.com/facebookresearch/demucs); [LICENSE](https://raw.githubusercontent.com/facebookresearch/demucs/main/LICENSE)
- HT Demucs MUSDB18 SDR: 7.52 dB overall / 7.93 vocals without extra data; 9.00 overall / 9.20 vocals with 800 extra songs (table in SCNet paper, 2024). — [SCNet arXiv 2401.13276](https://arxiv.org/pdf/2401.13276)
- BS-RoFormer (ByteDance, Lu/Wang/Kong/Hung): ranked first in the MSS track of Sound Demixing Challenge 2023 (trained with MUSDB18-HQ + 500 extra songs); a smaller variant reached 9.80 dB average SDR without extra data. — [search summary of BS-RoFormer/related papers; see arXiv 2412.06965](https://arxiv.org/pdf/2412.06965); patent [USPTO 12542148](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12542148)
- Open BS-RoFormer implementations are MIT: lucidrains/BS-RoFormer — [LICENSE](https://raw.githubusercontent.com/lucidrains/BS-RoFormer/main/LICENSE); ZFTurbo Music-Source-Separation-Training (community training framework for MDX/RoFormer models) — [LICENSE](https://raw.githubusercontent.com/ZFTurbo/Music-Source-Separation-Training/main/LICENSE). (Note: community-trained checkpoints may carry their own terms and are trained on varied data.)
- Commercial separation APIs: Music.AI (Moises) per-minute prices — musical stems $0.07/min, vocals $0.10/min, instrumental $0.05/min, drum stems $0.15/min (PAYG). — [music.ai/pricing](https://music.ai/pricing/)
- AudioShake bills credits per minute of source audio per target model, rounded up to the nearest minute; volume pricing via sales. — [AudioShake developer billing docs](https://developer.audioshake.ai/billing.md)
- LALAL.AI is subscription-based (G2 lists Lite $9.99/mo, Pro $19.99/mo; API access only on Pro); price figures differ across aggregators. — [G2 LALAL.AI pricing](https://g2.com/products/lalal-ai/pricing); [Toolradar](https://toolradar.com/tools/lalal-ai/pricing)

**Audio → piano cover models**
- Pop2Piano (Choi & Lee, ICASSP 2023): T5-based encoder-decoder that generates piano covers directly from pop audio spectrograms with no melody/chord extractor; trained on a ~300-hour synchronized pop/piano-cover dataset; available in Hugging Face Transformers. — [arXiv 2211.00895](https://arxiv.org/pdf/2211.00895); [HF model card](https://huggingface.co/sweetcocoa/pop2piano)
- PiCoGen (2024): two-stage approach (lead sheet extraction → piano generation). — [arXiv 2407.20883](https://arxiv.org/pdf/2407.20883)
- PiCoGen2 (Tan, Ai, Chang, Guan, Yang; ISMIR 2024): pre-trains on piano-only data then fine-tunes on weakly aligned pop/cover pairs built without note remapping. — [arXiv 2408.01551](https://arxiv.org/pdf/2408.01551); [ISMIR 2024 poster](https://ismir2024program.ismir.net/poster_114.html)
- AMT-APC (Komiya & Fukuhara, Musashino Univ., Sept 2024): fine-tunes a pre-trained AMT model for piano cover generation; authors claim it reproduces original tracks more accurately than prior models. Code MIT-licensed. — [arXiv 2409.14086](https://arxiv.org/pdf/2409.14086); [LICENSE](https://raw.githubusercontent.com/misya11p/amt-apc/main/LICENSE)
- Etude (Chen & Joung, arXiv Sept 2025, v2 Jan 2026): three-stage Extract (AMT-APC-derived extractor) → strucTUralize (Beat-Transformer beats/downbeats) → DEcode (~25.5M-param GPT-NeoX decoder, bar-by-bar with 4-bar context, Tiny-REMI tokens). Dataset ~7,700 pop/cover pairs (mostly J-pop/K-pop), 4,752 pairs (~500 h) after filtering. — [arXiv 2509.16522](https://arxiv.org/html/2509.16522v2)
- Etude subjective results (1–5 scale, OVL = overall): Human 3.92; Etude-Default 3.50; PiCoGen2 2.97; AMT-APC 2.46; Etude significantly beats PiCoGen2, AMT-APC and Music2MIDI (p<0.001). Controllability is via style attributes (polyphony, rhythmic intensity, note sustain), not pedagogical difficulty levels. — [arXiv 2509.16522](https://arxiv.org/html/2509.16522v2)
- Music2MIDI (Yip & Chau, ICMM 2025) also targets MIDI piano covers for pop music. — [search summary referencing Etude/related work, arXiv 2509.16522](https://arxiv.org/abs/2509.16522)
- PianoBind (2025): multimodal joint embedding model for pop-piano music (potentially useful for retrieval/evaluation of covers). — [arXiv 2509.04215](https://arxiv.org/pdf/2509.04215)

**Difficulty-based arrangement / simplification**
- "Difficulty-Controlled Simplification of Piano Scores with Synthetic Data" (Ramoneda, Parada-Cabaleiro, Jeong, Serra; Nov 2025): transformer that lowers difficulty of MusicXML piano scores, trained on a synthetic dataset of score pairs ordered by estimated difficulty (PianoPairs). — [arXiv 2511.16228](https://arxiv.org/html/2511.16228v1)
- Gover & Zewi (ISMIR 2022) "Music Translation: Generating Piano Arrangements in Different Playing Levels" used a parallel dataset of arrangements from a piano learning app and proposed the MuTE metric. — [ISMIR 2022 paper](https://archives.ismir.net/ismir2022/paper/000003.pdf)
- Suzuki (EURASIP JASMP 2023) rearranged piano scores across four difficulty levels with a difficulty-conditioned sequence model; Terao, Nakamura, Yoshii (ICASSP 2023) converted band scores into piano scores with stepless difficulty control. — [EURASIP JASMP 2023](https://doaj.org/article/8dfb47046d864e6a8a44d2aa93f84df4); [ICASSP 2023 video](https://rc.signalprocessingsociety.org/conferences/icassp-2023/spsicassp23vid0483)
- Nakamura et al., statistical piano reduction controlling performance difficulty (includes a fingering-motion model). — [Cambridge/APSIPA paper](https://www.cambridge.org/core/services/aop-cambridge-core/content/view/EB23810939F49C01EBF8C64C57F3DCC2/S2048770318000185a.pdf/statistical-piano-reduction-controlling-performance-difficulty.pdf); [arXiv 1808.05006](https://ar5iv.arxiv.org/html/1808.05006)

**Fingering / hand separation**
- PIG dataset (Nakamura et al., 2019): 150 pieces, 309 fingering annotations; higher-order HMMs outperformed DNNs at the time. — [arXiv 1904.10237](https://arxiv.org/pdf/1904.10237)
- Checklist models (2022) for fluent fingering prediction trained on PIG (up to 6 human fingerings per piece). — [arXiv 2209.05622](https://arxiv.org/pdf/2209.05622)
- "At Your Fingertips" (2023): extracts fingering from videos to build a larger dataset (APFD); fine-tuning on PIG improves over the PIG-only state of the art. — [arXiv 2303.03745](https://arxiv.org/pdf/2303.03745)
- PianoMotion10M (ICLR 2025 Spotlight): large hand-motion dataset aimed at piano fingering guidance. — [arXiv 2406.09326](https://arxiv.org/abs/2406.09326v2)
- Gover & Zewi's dataset coming from "a piano learning app" shows incumbents already hold parallel level-graded arrangements. — [ISMIR 2022 paper](https://archives.ismir.net/ismir2022/paper/000003.pdf)

**Commercial signal**
- Songscription ($5M round, Nov 2025, led by Reach Capital) earmarks funds for "automatic leveling and arrangement of pieces" and, longer-term, a learning app with live performance feedback; claims 150,000+ users in 150 countries. — [Magnetic Mag](https://magneticmag.com/2025/11/songscription-secures-5m-to-push-ai-music-transcription-forward/); [Techleap](https://finder.techleap.nl/news/feed/songscription-raises-5m-for-ai-sheet-music)

### Inferences
- A pragmatic pipeline for a startup in 2026: separation (HTDemucs/BS-RoFormer, MIT code) → beats/downbeats (Beat This!) → chords + melody extraction → symbolic arranger conditioned on difficulty → hand split + fingering → quantize/engrave. End-to-end models (Pop2Piano/Etude) give "listenable" covers but no explicit difficulty or hand assignment, which a tutorial app needs.
- The gap between Etude (3.50) and humans (3.92) plus the absence of pedagogical difficulty control is exactly where proprietary data (human-arranged, level-graded, fingered pieces + user corrections) creates a moat.
- Incumbents (Simply/JoyTunes, Flowkey, Skoove, Yousician) already own large level-graded arrangement catalogues (Gover & Zewi used one), giving them a data head start for training arrangers.

### Gaps
- License of Pop2Piano weights, PiCoGen/PiCoGen2 code, and Etude code not confirmed (no LICENSE found / not stated).
- No head-to-head, same-protocol benchmark of BS-RoFormer vs HTDemucs vs commercial APIs on piano/keys stems found.
- No dedicated 2024–2026 hand-separation (left/right hand) model paper found in this session.
- Chord recognition and melody extraction SOTA (e.g., specific 2024–26 models and licenses) were not researched in depth due to scope; Klangio and Music.AI sell chord recognition as an API (see §5).

## 3. Notation output: MIDI → MusicXML, beat tracking, engraving

### Takeaway
Rendering is commodity and open source (Verovio LGPL-3.0, OSMD BSD-3, MuseScore GPL), and beat tracking has a strong MIT-licensed 2024 model (Beat This!). The weak link is performance-MIDI → readable score (quantization, voicing, hand staves), which only recently got end-to-end transformer research (2024) and is still a hard, differentiating step.

### Cited Findings
- Beat This! (Foscarin, Schlüter, Widmer, ISMIR 2024): beat tracker that surpasses prior SOTA in F1 without DBN post-processing (worse on continuity metrics); trained on diverse data incl. solo instruments, time-signature changes and classical tempo variation; code, model and preprocessed data published. — [arXiv 2407.21658](https://arxiv.org/abs/2407.21658); [README](https://github.com/CPJKU/beat_this)
- Beat This! code license: MIT (JKU Linz, 2024). — [LICENSE](https://raw.githubusercontent.com/CPJKU/beat_this/main/LICENSE)
- madmom: source code BSD-style, but all model and data files are CC BY-NC-SA 4.0 (non-commercial) — i.e., madmom's pretrained beat/chord/onset models cannot be used commercially without permission. — [madmom LICENSE](https://raw.githubusercontent.com/CPJKU/madmom/main/LICENSE)
- Etude uses a pre-trained Beat-Transformer for beat/downbeat grid as the "structuralize" step, showing beat grids are key to musically coherent covers. — [arXiv 2509.16522](https://arxiv.org/html/2509.16522v2)
- End-to-End Piano Performance-MIDI to Score Conversion with Transformers (2024): converts performance MIDI to notation; code and models on GitHub. — [arXiv 2410.00210](https://arxiv.org/html/2410.00210v1)
- RUMAA (Chang, Dixon, Benetos; WASPAA 2025): aligns MusicXML scores (incl. repeats) to full performance audio and does score-informed transcription + mistake detection. — [arXiv 2507.12175](https://arxiv.org/abs/2507.12175)
- Rubato (arXiv 2605.24291, 2026): transcribing piano with timestamps; claims SOTA downbeat grounding while competitive on note transcription. — [arXiv 2605.24291](https://arxiv.org/html/2605.24291)
- Verovio: LGPL-3.0 (COPYING.LESSER alongside GPL-3.0 text in repo). — [verovio COPYING.LESSER](https://raw.githubusercontent.com/rism-digital/verovio/develop/COPYING.LESSER)
- OpenSheetMusicDisplay (OSMD): BSD-3-style license (Copyright PhonicScore). — [OSMD LICENSE](https://raw.githubusercontent.com/opensheetmusicdisplay/opensheetmusicdisplay/master/LICENSE)
- Songscription describes separate models: audio → MIDI, and MIDI → sheet music. — [Songscription audio-to-MusicXML page](https://www.songscription.ai/audio-to-musicxml)

### Inferences
- For a "falling notes" (Synthesia-style) tutorial, quantized MIDI + beat grid suffices; sheet music adds a costly quantization/voicing/hand-split step but matters for credibility with serious learners.
- Avoid madmom pretrained models in a commercial product (CC BY-NC-SA); Beat This! (MIT) is the natural replacement.
- Verovio (LGPL) is usable in closed apps with dynamic linking/WASM; OSMD (BSD) is the most permissive web renderer.

### Gaps
- MuseScore license was not re-checked in this session (generally GPL-3.0 — unverified here).
- Beat This! weights license not explicitly stated beyond the MIT code license.
- No quantitative benchmark found for MIDI→MusicXML quality of commercial tools.

## 4. Real-time "listening" to the learner

### Takeaway
Real-time assessment is a much easier problem than open transcription because the app knows the expected notes (score-informed detection): incumbents (Simply Piano's MusicSense, Yousician) have done mic-based listening for a decade, with MIDI as the accurate fallback. Latency is dominated by audio buffers/BLE intervals (~7–11 ms for BLE MIDI), not models. Score-following + mistake detection research (RUMAA 2025, streaming transcription 2025) is maturing, so this is table stakes, not a moat.

### Cited Findings
- Simply (formerly JoyTunes) uses a patented acoustic note recognition engine, "MusicSense", that listens via microphone and gives real-time feedback for piano, guitar and singing. — [Wikipedia: JoyTunes](https://www.wikipedia.com/wiki/JoyTunes)
- Simply's engineering blog: courses require chords of up to 5 simultaneous notes; room noise and the app's own backing track picked up by the mic are major challenges; headphones and concert-pitch (A=440) tuning are recommended to improve recognition. — [Simply engineering blog (Medium) "A look under the hood of Simply Piano, part 2"](https://medium.com/hellosimply/a-look-under-the-hood-of-simply-piano-part-2-3ba3cafa1bbf); [Simply help center](https://help.joytunes.com/en/articles/6210583-ways-to-improve-note-recognition-in-simply-piano-for-ios-acoustic-piano)
- MIDI connection is more accurate than mic because it reports exactly which key and how long it was held. — [Simply help/reviews summary, Pianist Magazine](https://www.pianistmagazine.com/blogs/simply-piano-a-piano-learning-app-for-beginner-pianists-and-above)
- BLE MIDI latency: measured ~7 ms (range 3–11 ms) between CME WIDI devices and 6–8 ms average to a BT 5.2 computer; the BLE minimum connection interval is 7.5 ms (pre-Bluetooth 6.2); Bluetooth 6.2 allows shorter intervals. (User measurement, not lab test.) — [Thomann CME WIDI Uhost review](https://www.thomann.de/be/cme_widi_uhost.htm); [Nordic DevZone](https://devzone.nordicsemi.com/f/nordic-q-a/29350/reducing-latency---ble-nano-as-midi-controller/119507)
- Google patent on "latency enhanced note recognition" by analyzing transient frames (US9640157B1). — [Google Patents](https://patents.google.com/patent/US9640157)
- Streaming piano transcription (2025) shows causal, low-compute models can match offline SOTA on MAESTRO. — [arXiv 2503.01362](https://arxiv.org/abs/2503.01362)
- RUMAA (2025) unifies score alignment, score-informed transcription and mistake detection — the core primitives of a "listening" tutor. — [arXiv 2507.12175](https://arxiv.org/abs/2507.12175)
- PianoVision (Meta Quest 2/3/3S/Pro): mixed-reality falling notes aligned on a real keyboard via passthrough + hand tracking; with MIDI connected (via desktop bridge app or USB-C) it waits for the correct note; "Air Piano" hand-tracking mode can miss inputs/ghost notes; v2.0 added "Ludwig" AI teacher; base app ~$9.99 with 1,000+ public-domain songs; PianoVision Plus subscription unlocks 10,000+ popular songs. — [Mixed News v2.0](https://mixed-news.com/en/piano-vision-update-2-0/); [UploadVR](https://uploadvr.com/pianovision-impressions-quest-2/); [Pianoers review](https://pianoers.com/pianovision-review/); [Quest store DB](https://queststoredb.com/app/pianovision-5271074762922599/)

### Inferences
- A new entrant can reach parity on listening by (a) supporting USB/BLE MIDI first (trivial, exact), and (b) running a small score-informed detector on-device for acoustic pianos; the model need only verify "did expected notes occur within a time window," which tolerates far lower raw accuracy than open transcription.
- The hardest real-world issue is acoustic: backing track bleed and room noise (per Simply's own blog), handled by echo cancellation/headphones rather than better models.

### Gaps
- No public technical details on Yousician's or Simply's recognition algorithms or measured end-to-end latency.
- No published mic-based polyphonic detection accuracy on phones for consumer pianos.
- Light-up keyboard ecosystems (e.g., The ONE, Roli/Lumi) were not researched in this session.

## 5. Buy option: commercial transcription APIs and pricing

### Takeaway
Buying is cheap and immediate: Klangio sells a transcription/separation/chords/beats API at $0.10–0.20 per request (≤5–10 min audio) and Music.AI (Moises) sells per-minute modules ($0.04–0.15/min). A full "stems + transcription + chords + beats" pass on a 4-min song costs roughly $1 or less via APIs vs. cents self-hosted. None of the buy options produce a pedagogically levelled piano arrangement, which is the actual product.

### Cited Findings
- Klangio API: endpoints for music transcription (MIDI, MusicXML, PDF, GP5; piano, guitar, bass, vocals), source separation, beat tracking (beats/downbeats/BPM/meter), strum and chord recognition. Pricing: Basic $0 (50 requests, 15 s max audio); Startup $99/mo (500 requests, $0.20 overage, 300 s max); Business $499/mo (3,000 requests, $0.17 overage, 300 s); Enterprise (10,000 requests, $0.10 overage, 600 s max). — [klang.io/api](https://klang.io/api/)
- Music.AI (Moises) module pricing (PAYG): General Purpose Transcription $0.08/min; Chords $0.04/min; Beats $0.03/min; Sections $0.04/min; musical stems $0.07/min; Professional plan $25/mo with 5% discount; Business/Enterprise custom. — [music.ai/pricing](https://music.ai/pricing/)
- AnthemScore (Lunaverus): desktop one-time licenses (third-party reported ~$31 Lite / ~$42 Professional / ~$107 Studio), 30-day trial; web version Free / Plus $9.99/mo / Pro $29.99/mo. — [Lunaverus web pricing](https://lunaverus.com/transcribe/pricing); [Lunaverus bulk purchase](https://www.lunaverus.com/bulkPurchase)
- Songscription: consumer/edu web platform (piano, violin, flute, guitar, bass, trumpet; outputs sheet music, MIDI, MusicXML, Guitar Pro); raised $5M (Nov 2025); no public developer API found (songscription.ai/api returned 404 on 2026-10-19). — [Magnetic Mag](https://magneticmag.com/2025/11/songscription-secures-5m-to-push-ai-music-transcription-forward/); [Preqin profile](https://www.preqin.com/data/profile/asset/songscription--inc-/778066)
- AudioShake: per-minute-per-model credit billing; volume via sales. — [AudioShake billing docs](https://developer.audioshake.ai/billing.md)

### Inferences
- Rough buy-side cost per 4-min song via Music.AI: stems ($0.28) + transcription ($0.32) + chords ($0.16) + beats ($0.12) ≈ $0.88; via Klangio ≈ $0.10–0.20 per call × 2–4 calls ≈ $0.30–0.80. Self-hosted open models: likely < $0.05 per song in GPU time (see §1). Buying makes sense for an MVP; at scale (100k+ songs/month) self-hosting saves tens of thousands of dollars/month.
- Klangio's 300 s cap on Startup/Business plans excludes many full-length pop songs (>5 min) without chunking.
- APIs output transcriptions, not difficulty-levelled, fingered, hand-separated arrangements — the core of a tutorial product must be built either way.

### Gaps
- AudioShake per-model credit rates and LALAL.AI API rates not published in sources found.
- No accuracy benchmarks comparing commercial APIs (Klangio, Music.AI, AnthemScore) to open models.
- Music.AI's "General Purpose Transcription" output format (MIDI vs. other) not confirmed on the pricing page.

## 6. Training data and its licensing

### Takeaway
The canonical datasets are non-commercial (MAESTRO CC BY-NC-SA 4.0, madmom models CC BY-NC-SA), and the data that actually powers pop→piano cover models (thousands of pop songs paired with YouTube piano covers) is copyrighted on both sides. A startup should assume that clean, licensed training data — or synthetic data plus its own user-generated corrections — is a real cost and a real moat.

### Cited Findings
- MAESTRO: ~200 hours of virtuosic piano performances from the International Piano-e-Competition, ~3 ms audio/MIDI alignment, mostly classical repertoire. — [Magenta MAESTRO page](https://magenta.withgoogle.com/datasets/maestro)
- MAESTRO is licensed CC BY-NC-SA 4.0 (non-commercial, share-alike). — [mirdata MAESTRO loader docs](https://mirdata.readthedocs.io/en/0.3.8/_modules/mirdata/datasets/maestro.html); [arXiv 2605.06685](https://arxiv.org/pdf/2605.06685)
- Whether a model trained on MAESTRO is an "adaptation" under the license is legally unsettled; a 2026 paper took the cautious approach of releasing transcribed MIDI only where permitted under CC BY-NC-SA 4.0. — [arXiv 2605.06685](https://arxiv.org/pdf/2605.06685)
- POP909 (ISMIR 2020): 909 pop songs as piano arrangements with MELODY / BRIDGE / PIANO tracks plus beat and chord annotations — designed for arrangement generation. — [POP909 repo](https://github.com/music-x-lab/POP909-Dataset); [arXiv 2008.07142](https://arxiv.org/abs/2008.07142)
- Pop2Piano trained on ~300 h of synchronized pop / piano-cover pairs; Etude on ~7,700 collected pop/cover pairs (mostly J-pop/K-pop), ~500 h after filtering. — [arXiv 2211.00895](https://arxiv.org/pdf/2211.00895); [arXiv 2509.16522](https://arxiv.org/html/2509.16522v2)
- Aria-MIDI (EleutherAI, 2025): large piano MIDI dataset built by transcribing web piano audio with Aria-AMT; Aria models and MIDI tooling released under Apache-2.0. — [arXiv 2504.15071](https://arxiv.org/html/2504.15071v1); [HF aria-medium card](https://huggingface.co/loubb/aria-medium)
- Synthetic data is an increasingly used route: MuScriptor (2026) uses synthetic pre-training + real-audio fine-tuning + RL post-training; difficulty-controlled simplification (2025) trains on a synthetic PianoPairs dataset. — [arXiv 2607.08168](https://arxiv.org/abs/2607.08168); [arXiv 2511.16228](https://arxiv.org/html/2511.16228v1)
- YourMT3+ training mix includes MIR-ST500 ("licensed mix-tracks by professional artists") among ~10 datasets; the paper does not state license terms for most datasets. — [arXiv 2407.04822v2](https://arxiv.org/html/2407.04822v2)
- madmom pretrained models/data: CC BY-NC-SA 4.0. — [madmom LICENSE](https://raw.githubusercontent.com/CPJKU/madmom/main/LICENSE)

### Inferences
- Commercial risk ranking (my judgement): using MAESTRO-trained piano weights = moderate (NC/SA ambiguity); using pop→cover models trained on scraped YouTube covers = high (copyright in both source recordings and cover arrangements); synthetic + licensed + user-generated data = lowest.
- Separately from model training, the product itself (generating arrangements of copyrighted songs on demand) needs publishing/sync rights strategy — incumbents (Simply Piano, Flowkey, PianoVision Plus) license catalogues of popular songs; this is a business/legal cost, not a technical one. (PianoVision Plus advertising 10,000+ popular songs: [Mixed News](https://mixed-news.com/en/piano-vision-update-2-0/).)

### Gaps
- POP909 license not found in README during this session.
- No legal precedent found specifically on models trained on CC BY-NC datasets.
- Publishing/mechanical licensing costs for user-uploaded songs were not researched (out of scope for technology notes).

## 7. Where is the real moat, and what does it cost?

### Takeaway
Not in transcription models or GPU cost (both commoditized: open MIT/Apache models at 97–98% piano F1, <$0.05/song compute, $0.10–0.90/song via APIs), and not in latency (MIDI/BLE is ~10 ms; listening is a solved, score-informed problem). Defensibility comes from (1) arrangement quality with real difficulty levels, hand split and fingering — where SOTA is still measurably below humans — and (2) a proprietary data flywheel of level-graded, user-corrected arrangements plus learner-performance data, wrapped in (3) pedagogy and content licensing.

### Cited Findings
- Best academic cover generator (Etude) still trails human arrangers: 3.50 vs 3.92 overall on 5-pt scale; offers style controls but not difficulty levels. — [arXiv 2509.16522](https://arxiv.org/html/2509.16522v2)
- Funded players are moving exactly here: Songscription's $5M is earmarked for "automatic leveling and arrangement" and a learning app with live performance feedback. — [Magnetic Mag](https://magneticmag.com/2025/11/songscription-secures-5m-to-push-ai-music-transcription-forward/)
- Level-graded parallel arrangement data already exists inside piano-learning apps (used in Gover & Zewi, ISMIR 2022). — [ISMIR 2022](https://archives.ismir.net/ismir2022/paper/000003.pdf)
- Multi-instrument transcription remains hard (only 2 of 8 teams beat MT3 in the 2025 AMT Challenge). — [arXiv 2603.27528](https://arxiv.org/abs/2603.27528)
- Solo-piano transcription is saturated on benchmark (Transkun v2 98.32 note F1) and permissively licensed. — [arXiv 2404.09466](https://arxiv.org/html/2404.09466); [Transkun LICENSE](https://raw.githubusercontent.com/Yujia-Yan/Transkun/main/LICENSE)
- GPU price reference: L4 ~$0.80/h on Modal; YourMT3+ transcribes ~6 min audio in <10 s on Ampere GPUs. — [Spheron/Modal pricing](https://www.spheron.network/blog/modal-gpu-pricing-2026-per-second-billing/); [arXiv 2407.04822v2](https://arxiv.org/html/2407.04822v2)
- API price reference: Klangio $0.10–0.20/request; Music.AI $0.03–0.15/min per module. — [klang.io/api](https://klang.io/api/); [music.ai/pricing](https://music.ai/pricing/)

### Inferences
- Estimated GPU cost per song (self-hosted, my estimate): separation (~10–30 s GPU) + transcription (~5–10 s) + beat/chord (~1–5 s) + symbolic arrangement decoding (~5–20 s with a ~25M-param decoder like Etude's) ≈ 20–60 s of L4 time ≈ $0.005–0.015 at list price; with cold-start/idle overhead budget ~$0.02–0.05/song. Caching popular songs (most users request the same hits) cuts effective cost further.
- Build-vs-buy recommendation implied by the evidence: buy (Klangio/Music.AI) or use open models for separation/transcription/beats; build the arranger (difficulty-conditioned, hand-split, fingered) and the correction UI that turns user edits into training data.
- Data flywheel mechanics: every user correction of a wrong note, hand assignment or fingering, and every learner performance (which notes people consistently fail at a given level) is supervised data that neither open datasets nor APIs provide; this compounds and is hard to copy.
- Latency is not a moat but a hygiene factor; poor latency/false negatives in mic mode is a churn risk (per Simply's documented noise/backing-track challenges).

### Gaps
- No public data on how many user corrections incumbents collect or how they use them.
- No measured end-to-end cost-per-song from any company; figures above are derived estimates.
- No user-research data comparing whether learners value arrangement quality vs. song selection vs. feedback accuracy most.
