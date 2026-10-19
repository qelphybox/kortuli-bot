# Legal/platform risks and investor landscape for an AI "any song to piano tutorial/sheet music" app (as of October 2026)

Not legal advice. These notes summarize statutes, guidance, platform rules and reported precedent. Every event is dated where the source gives a date. The research budget was about 22 tool calls, so many investor items are gaps (listed explicitly below).

## A1. Is an auto-generated transcription/arrangement of a copyrighted song a derivative work that needs a publisher licence? How do sheet-music platforms handle it?

### Takeaway
Under US law a musical arrangement is a derivative work. Only the copyright owner (usually the publisher) can authorise one, and the s.115 mechanical compulsory licence does not cover print or arrangement rights. Sheet-music platforms have moved toward licensed models: Ultimate Guitar signed an HFA licence (2010), MuseScore.com put downloads behind a paid Pro tier and said the reason was paying copyright owners, and Muse Group bought Hal Leonard (Dec 2023). Machine-generated output is not exempt. A piano score that reproduces a song's melody and harmony copies the underlying composition, whoever or whatever writes it down.

### Cited Findings
- US Copyright Office Circular 14 lists "musical arrangements" among derivative works ("new versions") and says the owner has the exclusive right "to prepare derivative works"; anyone else needs the owner's permission. — [Circular 14 (archived)](https://swap.stanford.edu/was/20151211033644mp_/http://copyright.gov/circs/circ14.pdf)
- Circular 50: registrable musical works include "original arrangements or other new versions of earlier compositions to which new copyrightable authorship has been added". — [USCO Circular 50](https://www.copyright.gov/circs/circ50.pdf)
- Circular 73a: the s.115 compulsory (mechanical) licence lets a licensee make an arrangement only to fit their style of interpretation. It does not allow changing "the basic melody or fundamental character of the work", and the licensee cannot claim copyright in the arrangement as a derivative work. So the mechanical licence does not grant print or sheet-music rights. — [USCO Circular 73a](https://www.copyright.gov/circs/circ73a.pdf)
- MTNA guidance for music teachers: a new arrangement of a copyrighted song is a derivative work and needs the rights holder's permission. — [MTNA Copyright FAQs](https://www.mtna.org/Copyright_FAQs.html)
- Ultimate Guitar reached a licensing agreement with the Harry Fox Agency in 2010 covering lyrics display, title search and tab display. — [Muse Group history](https://history.mu.se/)
- Ultimate Guitar acquired MuseScore / MuseScore.com. Wikipedia dates the deal to 2017 and Scoring Notes to 2018. Muse Group itself was formed in 2021. — [Wikipedia: Muse Group](https://en.wikipedia.org/wiki/Muse_Group); [Scoring Notes](https://www.scoringnotes.com/news/muse-group-acquires-hal-leonard/)
- MuseScore.com moved downloads behind MuseScore Pro (about $6.99/mo). A third-party downloader developer says the company told him this was about copyright and licensing, because it "must pay to the copyright owners", and that a MuseScore developer sent him a takedown request. A 2021 write-up notes that musescore.com hosts a mix of public-domain, Creative Commons and fully commercial works. These are secondhand accounts; I found no primary MuseScore or publisher statement about a 2019–2020 licensing deal. — [musescore-downloader README (gitdab)](https://gitdab.com/no-muse/musescore-downloader/src/commit/112f08470e555db155081545ce2cc64c2de2c9ce); [Michael Tsai blog, 2 Aug 2021](https://mjtsai.com/blog/?p=33297)
- Muse Group acquired Hal Leonard, the largest print-music publisher/distributor, closing 1 Dec 2023, with a growth investment from Francisco Partners (terms undisclosed). The combined library is over 5.5M scores, tabs, books, video courses and so on. Hal Leonard's "exclusively licensed, premium arrangements" are to be offered in interactive formats on Muse platforms. — [MBW](https://www.musicbusinessworldwide.com/music-creation-company-muse-group-acquires-sheet-music-publisher-hal-leonard-with-backing-from-private-equity-firm-francisco-partners); [Muse/Hal Leonard FAQ](https://www.mu.se/post/hal-leonard-combines-with-muse-group-faqs); [CDM, Dec 2023](https://cdm.link/2023/12/muse-group-hal-leonard/)
- After the merger, a MuseScore forum user observed Hal Leonard-published scores being offered for purchase on MuseScore.com (user comment, not official). — [musescore.org forum](https://musescore.org/en/comment/1132862)
- Hal Leonard bought Music Sales Group's (now Wise Music) sheet-music distribution business in 2018. A licensing dispute between the two was reported in July 2024. This shows how concentrated print/arrangement licensing is. — [CMU, 15 Jul 2024](https://completemusicupdate.com/hal-leonard-hits-back-at-wise-music-in-sheet-music-licensing-dispute/)
- Chordify's 2014 position: chord progressions alone are not distinctive enough to be copyrighted, and it removes individual songs when a rights owner asks. — [Digital Music News, 10 Mar 2014](https://www.digitalmusicnews.com/2014/03/10/chordify/)
- Songscription, the closest comparable "audio to notation" startup, says its models were trained on public-domain material and through partnerships with individual artists and music companies. It is negotiating with major publishers for more training data. Adviser Elizabeth Moody said "ethics are top of mind". MBW's coverage does not say how it licenses the output transcriptions of user-uploaded songs. — [MBW, 13 Nov 2025](https://www.musicbusinessworldwide.com/songscription-raises-5m-in-funding-as-shazam-for-sheet-music-platform-reaches-150k-users/)

### Inferences
- A piano tutorial that reproduces a song's melody, harmony and lyrics copies and adapts the composition. Under the US framework it is very likely an arrangement or reproduction that needs a print/arrangement licence from the publisher(s). Chordify's "chords aren't copyrightable" argument is weaker for a full piano score than for chord charts alone.
- Unlike mechanical rights, there is no compulsory print licence in the US. Print rights are negotiated directly with publishers or through print administrators: Hal Leonard (now Muse Group-owned), Alfred, Faber, Musicnotes and others. A competitor-owned administrator (Muse Group/Hal Leonard) holds a key licensing chokepoint. That is a strategic risk, and also a possible partner or buyer.
- The defensible "personal use / private transcription" argument (fair use for a user's own study) applies to the user. It is weaker for a commercial service that produces and sells the transcription. Fair use is case-by-case, and I found no court ruling on automated transcription services specifically.

### Gaps
- No primary source found for MuseScore.com's 2019–2020 publisher licensing deals and mass takedowns (widely remembered but not verified here).
- Not researched: how Musicnotes, Sheet Music Direct, Flowkey or Simply (Simply Piano) license songs, and their revenue-share terms with publishers (typical print royalty rates, e.g. a % of retail per sheet). No sources retrieved.
- No court decision found on whether AI-generated transcriptions are infringing or fair use.
- Copyright Office Compendium ch. 800 on transcriptions was not checked.

## A2. Fetching audio from YouTube/TikTok/Instagram links: ToS, yt-dlp, lawsuits, App Store rules, and how competitors handle it

### Takeaway
YouTube's Terms (dated 15 Dec 2023) forbid downloading content except as expressly authorised and forbid automated access. Apple's App Store Guideline 5.2.3 forbids apps that "save, convert, or download media from third-party sources (such as … YouTube …) without explicit authorization". A server-side yt-dlp pipeline behind a "paste a YouTube link" box therefore breaches YouTube's ToS and risks App Store rejection. Even so, several transcription tools (e.g. Klangio's Piano2Notes) are in the App Store advertising YouTube-link input. The tooling itself (youtube-dl) survived an RIAA §1201 takedown on GitHub in 2020.

### Cited Findings
- YouTube Terms of Service (dated/effective 15 Dec 2023): users may not "access, reproduce, download, distribute, transmit, broadcast, display… the Service or Content" except "as expressly authorized by the Service". They may not "access the Service using any automated means (such as robots, botnets or scrapers)" except public search engines under robots.txt. They may not circumvent features that "prevent or restrict the copying or other use of Content". — [YouTube Terms](https://www.youtube.com/static?template=terms)
- App Store Review Guideline 5.2.3: "Apps should not facilitate illegal file sharing or include the ability to save, convert, or download media from third-party sources (such as Apple Music, YouTube, SoundCloud, Vimeo, etc.) without explicit authorization from those sources. Streaming of audio/video content may also violate Terms of Use… Authorization must be provided upon request." — [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Guideline 5.2.2: an app that "uses, accesses, monetizes access to, or displays content from a third-party service" must be "specifically permitted to do so under the service's terms of use". Guideline 5.2.1: don't use copyrighted works without permission; apps should be submitted by whoever "owns or has licensed" the IP. — [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Developer reports of 5.2.3 rejections. Apple asked for "documentary evidence… showing the necessary rights or permissions" in App Store Connect. A reviewer said another approved app with the same feature "is never an argument". — [Apple Dev Forums thread 765340](https://developer.apple.com/forums/thread/765340); [thread 131199](https://developer.apple.com/forums/thread/131199); [thread 107843](https://developer.apple.com/forums/thread/107843)
- A browser app's developers said they removed downloading from official sites like YouTube and Vimeo to stay compliant (secondhand forum account). — [Aloha Browser community](https://community.alohabrowser.com/topic/help-me_8)
- RIAA vs youtube-dl (Oct–Nov 2020): the RIAA used DMCA §1201 (anti-circumvention), not §512, to get youtube-dl removed from GitHub. EFF argued the tool circumvents nothing. GitHub reinstated it on 16 Nov 2020 and now gives §1201 claims a technical and legal review, keeping projects up while a claim is disputed. — [EFF, Nov 2020](https://www.eff.org/deeplinks/2020/11/github-reinstates-youtube-dl-after-riaas-abuse-dmca); [9to5Google, 16 Nov 2020](https://9to5google.com/2020/11/16/youtube-dl-github-riaa-takedown/); [Digital Music News, 17 Nov 2020](https://www.digitalmusicnews.com/2020/11/17/youtube-dl-returns-to-github/)
- Klangio's Piano2Notes (App Store id1589420929) lets users upload MP3/WAV, record with the microphone, or paste a YouTube link to get a transcription. — [Apple App Store: Piano2Notes](https://apps.apple.com/app/id1589420929); [RunPod/Klangio blog](https://www.runpod.io/blog/klangio-ai-music-transcription-partnership)
- On embedding: the 2nd Circuit has found that YouTube's ToS can operate as a licence for third parties to show a video through the embedded player. That licence covers the video's display, not the underlying composition. — [Frankfurt Kurnit (FKKS) analysis](https://advertisinglaw.fkks.com/post/102mrvt/embedded-posts-copyright-infringement-tos-licensing-again)
- Background licensing: YouTube settled with the NMPA in 2011 and offered publishers licences, administered by HFA, for compositions in user videos. The majors had separate deals. HFA says it does not license users' YouTube uses. — [NMPA](https://www.nmpa.org/nmpa-reaches-resolution-of-copyright-infringement-lawsuit-against-youtube-agreement-results-in-new-licensing-opportunity-for-music-publishers/); [HFA help](https://help.harryfox.com/licensing-music-for-youtube-videos)

### Inferences
- The legal exposure from link-fetching has two layers. (1) Contract/ToS: YouTube can block, rate-limit or send cease-and-desist letters. Downloading copies is also arguably reproduction of the sound recording. (2) Platform distribution: Apple can reject or remove the app under 5.2.3/5.2.2. The App Store risk is the most immediate and practical one.
- Chordify-style designs apparently analyse audio while playing the official YouTube embed for playback, so users never get a downloaded file. This lowers, but does not remove, ToS risk. I found no source that describes Chordify's actual pipeline or YouTube agreement.
- Lower-risk patterns: (a) the user uploads a file they own or recorded (the "Shazam/microphone" model); (b) on-device listening via the microphone while the user plays the song in another app; (c) metadata-only link handling, where the app resolves song identity from the link and serves a licensed arrangement from a catalogue; (d) a web-only YouTube-link feature kept out of the iOS binary (a common workaround, but it still breaches YouTube's ToS).

### Gaps
- No lawsuits found against transcription apps (Moises, Chordify, Klangio, Songscription, Anything Piano) for YouTube fetching. No source found on Moises's or Anything Piano's link-handling policies.
- TikTok/Instagram ToS were not fetched.
- No source on whether Chordify has a licence or API agreement with YouTube.

## A3. Music-AI litigation 2024–2026 and what it means for training transcription models

### Takeaway
The labels-vs-Suno/Udio cases (filed 2024) mostly ended in late 2025 as settlements plus licensing deals: UMG–Udio (29 Oct 2025), Warner–Udio (19 Nov 2025), Warner–Suno (25 Nov 2025). The industry's message is "license, don't litigate". In Europe, GEMA beat OpenAI in Munich on 11 Nov 2025: memorised lyrics inside a model were held to be infringing reproductions. Publishers' lyrics case against Anthropic (filed Oct 2023) continues. A transcription model trained on unlicensed commercial recordings or sheet music carries similar risk, and investors will ask about training-data provenance.

### Cited Findings
- UMG and Udio settled on 29 Oct 2025 and agreed to launch a licensed subscription platform in 2026. Terms undisclosed. — [MBW](https://www.musicbusinessworldwide.com/universal-music-settles-udio-lawsuit-strikes-deal-for-licensed-ai-music-platform); [Digital Music News, 29 Oct 2025](https://www.digitalmusicnews.com/2025/10/29/umg-udio-ink-ai-licensing-agreement/)
- Warner and Udio settled (Nov 2025). Udio will move to a licensed subscription model, with artists opting in. — [Decrypt](https://decrypt.co/349360/warner-music-moves-from-litigation-to-licensing-with-udio?amp=1); [Mixmag](https://mixmag.net.au/read/warner-music-strikes-licensing-deal-with-ai-start-up-udio-following-infringement-settlement-news)
- Warner and Suno settled and formed a partnership (reported 25 Nov 2025). — [Bloomberg Law](https://news.bloomberglaw.com/ip-law/warner-music-settles-lawsuit-with-ai-music-startup-suno)
- As of Suno's Series C (19 Nov 2025), TechCrunch described Suno as still fighting suits from Sony, UMG and Warner (Warner then settled six days later). I found no confirmed UMG–Suno or Sony settlement. — [TechCrunch, 19 Nov 2025](https://techcrunch.com/2025/11/19/legally-embattled-ai-music-startup-suno-raises-at-2-45b-valuation-on-200m-revenue/)
- Concord/UMG/ABKCO v. Anthropic (filed Oct 2023). In Dec 2024 a court-approved partial stipulation required Anthropic to keep its existing lyric "guardrails". A preliminary injunction was denied as overbroad, with no irreparable harm shown. In Oct 2025 the court let claims over users' lyric infringement proceed, and publishers moved to amend to add piracy (torrenting) claims. — [Canadian Lawyer](https://www.canadianlawyermag.com/news/international/ai-company-anthropic-agrees-to-chatbot-guardrails-in-lyrics-lawsuit/390493); [Heather Meeker, 4 Jan 2025](https://heathermeeker.com/2025/01/04/anthropic-settles-a-small-part-of-an-ai-copyright-claim/); [Bloomberg Gov, Oct 2025](https://news.bgov.com/ip-law/anthropic-must-face-claims-over-users-song-lyric-infringement); [MBW: amended complaint](https://www.musicbusinessworldwide.com/music-publishers-file-amended-lyrics-lawsuit-against-anthropic-just-as-ai-firms-separate-1-5b-piracy-settlement-with-authors-wins-court-approval/)
- GEMA v. OpenAI, Landgericht München I, 42 O 14139/24, 11 Nov 2025. The court found that the models contained reproductions of the training lyrics (memorisation) and that simple prompts produced near-verbatim output. It granted an injunction, an information order and damages, and found at least negligence because OpenAI had known of memorisation risks since 2021. First-instance ruling, appealable. — [Bird & Bird](https://cm.twobirds.com/en/insights/2025/landmark-ruling-of-the-munich-regional-court-(gema-v-openai)-on-copyright-and-ai-training); [Heuking, 13 Nov 2025](https://www.heuking.de/en/news-events/newsletter-articles/detail/gema-vs-openai-landmark-ruling-on-ai-language-models-and-copyright-law.html); [Verfassungsblog, 19 Nov 2025](https://verfassungsblog.de/munich-regional-courts-ruling-in-gema-v-open-ai/)
- UMG and Sony have partnered on neural fingerprinting to detect infringement in AI-generated music (as reported Nov 2025). — [MBW, 13 Nov 2025](https://www.musicbusinessworldwide.com/songscription-raises-5m-in-funding-as-shazam-for-sheet-music-platform-reaches-150k-users/)

### Inferences
- For a transcription model, the output (a score of a user's song) is a bigger rights issue than training. Training data also matters: aligned audio and MIDI/score pairs from commercial recordings or Hal Leonard-type arrangements are exactly the material rightsholders are now licensing. Public-domain, synthetic, and commissioned or licensed datasets (Songscription's approach) are the defensible route.
- The GEMA ruling suggests that in the EU a model that can regurgitate copyrighted arrangements may itself count as a reproduction. A model that only maps audio to notes and does not memorise scores is less exposed.
- Expect investor diligence questions on: training-data provenance, opt-outs, output filtering for well-known copyrighted songs, and any publisher LOIs.

### Gaps
- Status of UMG/Sony v. Suno after Nov 2025, and any 2026 developments in the Anthropic case, were not verified against dockets. A search snippet mentioned a second publishers' suit (>20,000 songs, >$3B) but I could not date or confirm it from a primary source.
- No litigation found that targets transcription or stem-separation tools specifically.

## A4. Safe-harbour designs, and EU vs US differences

### Takeaway
In the US, DMCA §512 protects hosting of user-uploaded material but not a service's own generated output. Content the app itself transcribes and sells is the service's own act. In the EU, Art. 17 of the DSM Directive makes "online content-sharing service providers" directly liable unless they make best efforts to license. Startups under 3 years old with under €10M turnover get a lighter regime. A private-only, no-public-sharing design likely avoids OCSSP status. The most robust model is a licensed catalogue with publisher revenue share, for which Hal Leonard (now Muse Group) is the dominant gatekeeper.

### Cited Findings
- Art. 17(6) DSM Directive: services available in the EU for under 3 years with annual turnover under €10M face a lighter "best efforts to license + notice-and-takedown" regime. Above 5M average monthly unique visitors they must also prevent re-uploads. Non-profit encyclopaedias, educational/scientific repositories and open-source platforms are excluded. — [Copyright and Technology, 1 Apr 2019](https://copyrightandtechnology.com/2019/04/01/eu-article-13-now-article-17-passes-after-more-changes-making-copyright-filtering-more-likely/); [Audible Magic](https://audiblemagic.com/?p=5445); [DNS Belgium](https://dnsbelgium.be/en/article-17-formerly-art-13-upload-filter)
- The Commission's review of the small-OCSSP regime is due no sooner than 7 June 2026, as part of the DSM review, so the rules may change. — [Council doc ST-15441-2024](https://data.consilium.europa.eu/doc/document/ST-15441-2024-INIT/en/pdf)
- Chordify's operational stance has been per-song takedown on rightsholder request. — [Digital Music News, 2014](https://www.digitalmusicnews.com/2014/03/10/chordify/)
- Licensed-catalogue precedent: Ultimate Guitar–HFA (2010). Muse Group bought Hal Leonard (2023) to bring licensed arrangements into its apps. — [Muse Group history](https://history.mu.se/); [MBW](https://www.musicbusinessworldwide.com/music-creation-company-muse-group-acquires-sheet-music-publisher-hal-leonard-with-backing-from-private-equity-firm-francisco-partners)
- The Section 115 compulsory licence does not cover arrangements that change a work's fundamental character, so there is no statutory shortcut for print. — [USCO Circular 73a](https://www.copyright.gov/circs/circ73a.pdf)

### Inferences
- Risk-ranked design options, from lowest to highest risk:
  1. Licensed catalogue: arrangements licensed from publishers or via Hal Leonard/Musicnotes, plus public-domain songs. AI is used for difficulty levels and personalisation of licensed works.
  2. User-supplied file or microphone, output kept private to that user: no sharing, no public gallery, no export of print-quality PDFs, watermarked, per-song takedown process, and fingerprint-blocking of songs whose rightsholders object. This leans on the user's personal or educational use and avoids Art. 17 OCSSP status (no public sharing). It is still exposed, because the service makes the arrangement.
  3. Public sharing or a community gallery of AI transcriptions (MuseScore.com pre-licensing model): DMCA/Art. 17 exposure plus publisher pressure.
  4. Server-side YouTube/TikTok ripping: ToS and App Store violation risk on top of copyright.
- A middle path many founders take: launch with option 2, approach publishers early with fingerprinting and reporting, and offer per-stream or per-transcription revenue share. Songscription is negotiating such deals, per MBW.
- US vs EU: the US has fair use (uncertain, fact-specific) and DMCA §512 notice-and-takedown. The EU has no general fair use, narrower private-copy exceptions, Art. 17 for sharing platforms, and (post-GEMA) stricter attitudes to memorisation in models.

### Gaps
- No public data on revenue-share terms offered by Hal Leonard, Musicnotes, Kobalt or Sheet Music Plus to app developers.
- DMCA §512 applicability to AI-generated outputs was not sourced.

## B1. Funding rounds 2021–2026 in music-learning and music-AI

### Takeaway
Confirmed data points: Songscription $5M (Nov 2025, Reach Capital lead); Music AI/Moises $40M Series A (announced Jan 2025, Connect Ventures [CAA+NEA] and monashees); AudioShake $14M Series A (Oct 2025, Shine Capital); Suno $250M Series C at $2.45B post-money (Nov 2025, Menlo); JoyTunes/Simply $50M at $1B (2021, GV); Yousician $28M Series B (Apr 2021, True Ventures lead, with Amazon Alexa Fund and MPL Ventures). Music-learning valuations peaked in 2021. The 2024–2026 money has gone mainly to AI-native music tools.

### Cited Findings
- **Songscription** (audio to sheet music, "Shazam for sheet music"): $5M announced 13 Nov 2025, led by Reach Capital (which also led the prior round), with Emerge Capital, 10x Founders, Dent Capital and angel/adviser Ron "Bumblefoot" Thal. Over 150,000 users in 150 countries about 5 months after its June 2025 launch. Supports piano, violin, flute, guitar, bass and trumpet. — [MBW, 13 Nov 2025](https://www.musicbusinessworldwide.com/songscription-raises-5m-in-funding-as-shazam-for-sheet-music-platform-reaches-150k-users/); [Songscription blog](https://www.songscription.ai/blog/seed-funding-announcement)
- **Music AI (Moises)**: $40M Series A ($30M primary + $10M secondary), led by Connect Ventures (CAA × NEA) and monashees, with Kickstart, Samsung Next, Toba Capital, Valutia, Pelion and artists Freddy Wexler, 3LAU and Alexander23. Moises had 50M users. Hypebot dates the announcement 22 Jan 2025. About $50.2M raised in total across 3 rounds. Earlier rounds: $1.6M seed (Kickstart lead) and $8.65M (Aug 2022). Some trackers misdate the Series A (Jan 2024 / May 2025). No valuation disclosed. — [MBW](https://musicbusinessworldwide.com/music-ai-raises-40m-in-series-a-round-as-its-moises-platform-hits-50m-users); [Hypebot, 22 Jan 2025](https://www.hypebot.com/hypebot/2025/01/music-ai-adds-40-million.html); [Moises $8.65M release](https://moises.ai/blog/press-releases/moises-raises-8-65-million)
- **Simply (JoyTunes)**: $50M round at a $1B valuation, led by GV, with Qualcomm Ventures and Hearst Ventures (2021; Multiples.vc labels it a June 2021 Series D). — [Globes](https://en.globes.co.il/en/article-joytunes-raising-50m-at-1b-valuation-1001375306); [Global Venturing](https://globalventuring.com/corporate/google-drives-joytunes-to-unicorn-valuation)
  - Conflict: Multiples.vc claims Simply was "acquired by Yousician in 2021". This is unsupported elsewhere and likely wrong. — [Multiples.vc](https://multiples.vc/private-comps/simply)
- **Yousician**: $28M Series B, 28 Apr 2021. True Ventures is its lead investor; new investors included the Amazon Alexa Fund and Paul McCartney's MPL Ventures. No valuation disclosed. — [MBW](https://www.musicbusinessworldwide.com/yousician-raises-28m-in-b-round-new-investors-include-amazon-alexa-fund-and-paul-mccartneys-mpl-ventures%20); [CB Insights](https://www.cbinsights.com/company/ovelin/financials)
- **AudioShake** (stem separation): $14M Series A announced about 1 Oct 2025, led by Shine Capital, with Thomson Reuters Ventures, Origin Ventures, Background Capital, Indicator Ventures and Precursor Ventures. About $19M raised in total. — [AudioShake](https://www.audioshake.ai/post/series-a-round-raise-14-million-shinecapital-origin-thomson-reuters); [Digital Music News, 1 Oct 2025](https://www.digitalmusicnews.com/2025/10/01/audioshake-series-a)
- **Suno** (context): $250M Series C at a $2.45B post-money valuation, 19 Nov 2025, led by Menlo Ventures, with NVentures (NVIDIA), Hallwood Media, Lightspeed and Matrix. About $200M annual revenue. Prior round: $125M Series B in May 2024 at about $500M. — [TechCrunch, 19 Nov 2025](https://techcrunch.com/2025/11/19/legally-embattled-ai-music-startup-suno-raises-at-2-45b-valuation-on-200m-revenue/); [Suno blog](https://suno.com/blog/series-c-announcement); [Goodwin](https://www.goodwinlaw.com/en/news-and-events/news/2025/11/announcements-technology-goodwin-advises-suno-on-250-million-series-c-financing)
- **Klangio** (Piano2Notes and similar; Karlsruhe): support comes mainly from non-dilutive programmes (Start-up BW Pre-Seed, Ideenstark, CyberForum). A revenue tracker describes it as bootstrapped with no VC. — [thelaend.de profile](https://www.thelaend.de/en/unternehmensprofil-piano2note); [Latka](https://getlatka.com/companies/klang.io)
- **Muse Group / Hal Leonard**: the merger closed 1 Dec 2023, backed by Francisco Partners (PE). Terms undisclosed. — [PE Hub](https://pehub.com/francisco-partners-backs-merger-of-sheet-music-publisher-hal-leonard-and-music-apps-creator-muse-group)

### Inferences
- A comparable pre-seed/seed for an "any song to piano tutorial" app is Songscription's $5M (Nov 2025). Klangio shows a product in the same niche can be built without VC, which suggests the core transcription technology alone is not a strong moat.
- Investors in this space include edtech funds (Reach, Emerge), media/agency-linked funds (Connect Ventures/CAA), corporate VCs (Samsung Next, Amazon Alexa Fund, NVentures, Qualcomm, Hearst) and artist/rights-holder vehicles (MPL Ventures, Hallwood).

### Gaps
- No sources retrieved for: Musora, Melodics, Tonestro, Trala, Pianote, Tunely, Fender Play funding, Splice's latest round, or Simply/Yousician rounds after 2021 (or their valuations in 2024–2026).
- No valuation data for Songscription, Moises or AudioShake.

## B2. Repeat music-tech/edtech investors and what they expect at pre-seed/seed

### Takeaway
Repeat names confirmed in sources: Reach Capital (led two Songscription rounds), Emerge (Songscription), Kickstart and Samsung Next (Moises), True Ventures (Yousician), GV (Simply), Connect Ventures/CAA×NEA (Moises), Shine/Precursor/Indicator (AudioShake), Menlo/Lightspeed/Matrix (Suno), and label or artist vehicles (MPL Ventures, Hallwood Media). I found no sourced benchmarks for the pre-seed/seed metrics these funds expect.

### Cited Findings
- Reach Capital led both of Songscription's rounds; Emerge Capital, 10x Founders and Dent Capital participated (Nov 2025). — [MBW](https://www.musicbusinessworldwide.com/songscription-raises-5m-in-funding-as-shazam-for-sheet-music-platform-reaches-150k-users/)
- Connect Ventures (CAA × NEA) and monashees led Moises's Series A; Kickstart had led its seed, and Samsung Next, Toba and Pelion participated. — [MBW](https://musicbusinessworldwide.com/music-ai-raises-40m-in-series-a-round-as-its-moises-platform-hits-50m-users)
- True Ventures (lead), Amazon Alexa Fund and MPL Ventures invested in Yousician. — [MBW](https://www.musicbusinessworldwide.com/yousician-raises-28m-in-b-round-new-investors-include-amazon-alexa-fund-and-paul-mccartneys-mpl-ventures%20)
- GV, Qualcomm Ventures and Hearst Ventures invested in JoyTunes/Simply. — [Globes](https://en.globes.co.il/en/article-joytunes-raising-50m-at-1b-valuation-1001375306)
- Shine Capital, Thomson Reuters Ventures, Origin, Background, Indicator and Precursor invested in AudioShake. — [AudioShake](https://www.audioshake.ai/post/series-a-round-raise-14-million-shinecapital-origin-thomson-reuters)
- Menlo, NVentures, Hallwood Media, Lightspeed and Matrix invested in Suno. — [TechCrunch](https://techcrunch.com/2025/11/19/legally-embattled-ai-music-startup-suno-raises-at-2-45b-valuation-on-200m-revenue/)
- Traction signals cited at announcement: Songscription's 150K users in 5 months; Moises's 50M users; Suno's $200M revenue. — [MBW Songscription](https://www.musicbusinessworldwide.com/songscription-raises-5m-in-funding-as-shazam-for-sheet-music-platform-reaches-150k-users/); [MBW Moises](https://musicbusinessworldwide.com/music-ai-raises-40m-in-series-a-round-as-its-moises-platform-hits-50m-users); [TechCrunch](https://techcrunch.com/2025/11/19/legally-embattled-ai-music-startup-suno-raises-at-2-45b-valuation-on-200m-revenue/)

### Inferences
- The announcement messaging suggests investors weigh fast user growth (organic or viral) and a credible rights strategy, such as Songscription's publisher negotiations and named music-industry advisers.
- Founders should prepare a "rights plan" slide: data provenance, a takedown/fingerprinting process, publisher conversations, and the iOS distribution approach given Guideline 5.2.3.

### Gaps
- Not sourced: activity by Owl Ventures, Firstminute, Plus Eight Equity Partners, Techstars Music, Abbey Road Red, UMG/Warner/Sony venture arms, and Hal Leonard/Muse corporate development in this niche.
- No sourced benchmarks for pre-seed/seed MRR, retention, CAC payback or conversion rates for consumer music-learning subscriptions. This needs a dedicated search (e.g. RevenueCat State of Subscription Apps, investor blog posts).

## B3. Typical exits and acquirers in music edtech / music tech

### Takeaway
Confirmed exits and consolidation: Ultimate Guitar bought MuseScore (2017/2018); Muse Group (formed 2021) combined with Hal Leonard (Dec 2023, Francisco Partners); Fender bought Sonic Ladder/Riffstation (2017) and launched Fender Play; Splice bought Spitfire Audio (Apr 2025, about $50M per the FT). Buyers fall into three groups: platform consolidators (Muse Group, Splice), instrument makers (Fender) and PE.

### Cited Findings
- Ultimate Guitar acquired MuseScore BVBA (2017 per Wikipedia, 2018 per Scoring Notes). — [Wikipedia](https://en.wikipedia.org/wiki/Muse_Group); [Scoring Notes](https://www.scoringnotes.com/news/muse-group-acquires-hal-leonard/)
- Muse Group acquired Hal Leonard, closing 1 Dec 2023, with Francisco Partners. — [MBW](https://www.musicbusinessworldwide.com/music-creation-company-muse-group-acquires-sheet-music-publisher-hal-leonard-with-backing-from-private-equity-firm-francisco-partners); [PE Hub](https://pehub.com/francisco-partners-backs-merger-of-sheet-music-publisher-hal-leonard-and-music-apps-creator-muse-group)
- Hal Leonard bought Music Sales Group's (Wise) sheet-music distribution business in 2018. — [CMU, Jul 2024](https://completemusicupdate.com/hal-leonard-hits-back-at-wise-music-in-sheet-music-licensing-dispute/)
- Fender acquired Dublin-based Sonic Ladder (maker of Riffstation) in June 2017 as it entered online learning. Fender Play had over 100,000 active paying users in 2019. — [Music Inc., 12 Jun 2017](https://www.musicincmag.com/legacy/News/2017/061217/061217_Fender.html); [Fortune, 6 Jul 2017](https://fortune.com/2017/07/06/guitar-legend-fender-is-getting-into-the-online-learning-business)
- Fender launched a "Fender Songs" app built on Apple Music, an example of using a licensed streaming catalogue for play-along. — [American Songwriter](https://americansongwriter.com/fender-launches-new-app-fender-songs-offers-immersive-playing-experience-with-apple-music/?nb=1)
- Splice acquired Spitfire Audio, announced 28 Apr 2025. The price was undisclosed by Splice; the FT reported about $50M. — [DJ Mag](https://djmag.com/news/splice-acquires-spitfire-audio-virtual-instrument-company-reported-50-million); [RightsTech, Apr 2025](https://rightstech.com/2025/04/splice-acquires-spitfire-audio-for-a-reported-50m-as-it-bets-on-ai-music-creation/)

### Inferences
- The most natural strategic acquirer for an AI piano-transcription app is Muse Group/Hal Leonard. It owns MuseScore, Ultimate Guitar, a print catalogue and licensing relationships, so it is at once licensor, competitor and potential buyer. Other plausible buyers: Simply, Yousician, Fender, Splice, and instrument makers such as Yamaha, Roland and Casio. None of the instrument makers is confirmed in sources as an acquirer of a learning app.
- The Fender Songs/Apple Music pattern shows a licensed-catalogue route: partnering with a streaming service rather than ripping YouTube.

### Gaps
- Not found: 2024–2026 acquisitions by Yamaha, Roland, Native Instruments, UMG or Hal Leonard of learning apps; Musora deals; Yousician acquisitions (the GuitarTuna question from the brief was not verified; no source retrieved).
- No exit multiples or valuations for music-edtech acquisitions.
