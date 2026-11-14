// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit composition of the controls archived in Settings*.xib.
// Edit row membership here, independently of Interface Builder placeholder frames.
+ (NSDictionary<NSString *, TSSettingsLayoutGroup *> *)groups
{
    return @{
        @"settings.BCz-G7-Yrz": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.764"] kind:TSSettingsRowControls indentation:0], // consoleResizeMatrix
        ]],
        @"settings.706": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.752"] kind:TSSettingsRowSection indentation:0], // Console Font
            [TSSettingsLayoutRow controls:@[@"settings.WQX-9X-AFi"] kind:TSSettingsRowSection indentation:0], // Console Position
            [TSSettingsLayoutRow controls:@[@"settings.772"] kind:TSSettingsRowSection indentation:0], // Console Resize
            [TSSettingsLayoutRow controls:@[@"settings.828"] kind:TSSettingsRowSection indentation:0], // Show Console
        ]],
        @"settings.fU9-qN-0Tl": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.755", @"settings.754"] kind:TSSettingsRowControls indentation:0], // Set ...
            [TSSettingsLayoutRow controls:@[@"settings.Ot0-Z2-OiZ"] kind:TSSettingsRowControls indentation:0], // macroButton
        ]],
        @"settings.42C-eP-vDT": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.fMM-Lh-WMT"] kind:TSSettingsRowControls indentation:0], // consoleWindowPosMatrix
            [TSSettingsLayoutRow controls:@[@"settings.ySw-P2-zn6"] kind:TSSettingsRowControls indentation:1], // consoleWindowPosButton
        ]],
        @"settings.a7e-iG-Bgc": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.777"] kind:TSSettingsRowControls indentation:0], // consoleMatrix
        ]],
        @"settings.gq7-pV-IeW": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.935"] kind:TSSettingsRowSection indentation:0], // Parens Matching Settings
            [TSSettingsLayoutRow controls:@[@"settings.63"] kind:TSSettingsRowSection indentation:0], // Editor
            [TSSettingsLayoutRow controls:@[@"settings.4a3-VM-Tgq"] kind:TSSettingsRowSection indentation:0], // Wrap Lines
            [TSSettingsLayoutRow controls:@[@"settings.Gj7-Yx-1Hv"] kind:TSSettingsRowSection indentation:0], // Style
            [TSSettingsLayoutRow controls:@[@"settings.933"] kind:TSSettingsRowSection indentation:0], // Show Invisible Characters
        ]],
        @"settings.xo6-RL-dNk": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.939"] kind:TSSettingsRowControls indentation:0], // highlightContentButton
            [TSSettingsLayoutRow controls:@[@"settings.936"] kind:TSSettingsRowControls indentation:0], // showIndicatorForMoveButton
            [TSSettingsLayoutRow controls:@[@"settings.1035"] kind:TSSettingsRowControls indentation:0], // alwaysHighlightButton
            [TSSettingsLayoutRow controls:@[@"settings.938"] kind:TSSettingsRowControls indentation:0], // beepButton
            [TSSettingsLayoutRow controls:@[@"settings.937"] kind:TSSettingsRowControls indentation:0], // flashBackgroundButton
        ]],
        @"settings.c39-PI-VV1": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.9oZ-Jg-MfD"] kind:TSSettingsRowControls indentation:0], // tabIndentButton
            [TSSettingsLayoutRow controls:@[@"settings.3gb-2l-vK7"] kind:TSSettingsRowControls indentation:0], // syntaxColorLineButton
            [TSSettingsLayoutRow controls:@[@"settings.621"] kind:TSSettingsRowControls indentation:0], // Switch
        ]],
        @"settings.1BU-WH-vph": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.961", @"settings.957"] kind:TSSettingsRowControls indentation:0], // showSpaceCharacterButton
            [TSSettingsLayoutRow controls:@[@"settings.960", @"settings.956"] kind:TSSettingsRowControls indentation:0], // showFullwidthSpaceCharacterButton
            [TSSettingsLayoutRow controls:@[@"settings.959", @"settings.955"] kind:TSSettingsRowControls indentation:0], // showNewLineCharacterButton
            [TSSettingsLayoutRow controls:@[@"settings.958", @"settings.954"] kind:TSSettingsRowControls indentation:0], // showTabCharacterButton
            [TSSettingsLayoutRow controls:@[@"settings.1043"] kind:TSSettingsRowControls indentation:0], // showInvisibleCharactersButton
        ]],
        @"settings.YHA-fP-2KS": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.TUV-ZL-JgG"] kind:TSSettingsRowControls indentation:0], // wrapMatrix
        ]],
        @"settings.WI3-rY-4zR": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.9yz-Dw-vpr", @"settings.gri-fr-HQh"] kind:TSSettingsRowField indentation:0], // Tab Size:
            [TSSettingsLayoutRow controls:@[@"settings.hvY-fo-Je9", @"settings.G3h-FQ-M95"] kind:TSSettingsRowField indentation:0], // First Line Paragraph Indent:
            [TSSettingsLayoutRow controls:@[@"settings.LSg-IX-MdN", @"settings.JeQ-iL-Koo"] kind:TSSettingsRowField indentation:0], // Remaining Lines Paragraph Indent:
            [TSSettingsLayoutRow controls:@[@"settings.atO-Td-bwy", @"settings.F9P-G9-BX2"] kind:TSSettingsRowField indentation:0], // Interline Spacing:
        ]],
        @"settings.13": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.215"] kind:TSSettingsRowSection indentation:0], // Path settings
            [TSSettingsLayoutRow controls:@[@"settings.54"] kind:TSSettingsRowSection indentation:0], // pdfTeX
            [TSSettingsLayoutRow controls:@[@"settings.200"] kind:TSSettingsRowSection indentation:0], // TeX + dvips + distiller
            [TSSettingsLayoutRow controls:@[@"settings.1020"] kind:TSSettingsRowSection indentation:0], // Search command
            [TSSettingsLayoutRow controls:@[@"settings.1027"] kind:TSSettingsRowSection indentation:0], // BibTeX Engine
        ]],
        @"settings.C6f-GQ-WQW": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.218", @"settings.217"] kind:TSSettingsRowField indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.256", @"settings.255"] kind:TSSettingsRowField indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.PsG-fR-sPc", @"settings.oMY-Ya-GFE"] kind:TSSettingsRowField indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.engine-auto-button"] kind:TSSettingsRowControls indentation:0], // Auto Setup…
        ]],
        @"settings.gPH-WT-0Et": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.52", @"settings.1062"] kind:TSSettingsRowControls indentation:0], // TeX
            [TSSettingsLayoutRow controls:@[@"settings.51"] kind:TSSettingsRowControls indentation:0], // texCommandTextField
            [TSSettingsLayoutRow controls:@[@"settings.50", @"settings.1070"] kind:TSSettingsRowControls indentation:0], // LaTeX
            [TSSettingsLayoutRow controls:@[@"settings.53"] kind:TSSettingsRowControls indentation:0], // latexCommandTextField
            [TSSettingsLayoutRow controls:@[@"settings.325"] kind:TSSettingsRowControls indentation:0], // escapeWarningButton
        ]],
        @"settings.Vh1-Vx-3JF": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.1066", @"settings.1067"] kind:TSSettingsRowControls indentation:0], // TeX
            [TSSettingsLayoutRow controls:@[@"settings.202"] kind:TSSettingsRowControls indentation:0], // texGSCommandTextField
            [TSSettingsLayoutRow controls:@[@"settings.1072", @"settings.1073"] kind:TSSettingsRowControls indentation:0], // LaTeX
            [TSSettingsLayoutRow controls:@[@"settings.199"] kind:TSSettingsRowControls indentation:0], // latexGSCommandTextField
            [TSSettingsLayoutRow controls:@[@"settings.225"] kind:TSSettingsRowControls indentation:0], // savePSButton
        ]],
        @"settings.DBm-wM-PDK": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.1021", @"settings.1022"] kind:TSSettingsRowField indentation:0],
        ]],
        @"settings.xP2-FB-CFh": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.1029", @"settings.1028"] kind:TSSettingsRowField indentation:0],
        ]],
        @"settings.400": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.386"] kind:TSSettingsRowSection indentation:0], // Image Copy Type
            [TSSettingsLayoutRow controls:@[@"settings.447"] kind:TSSettingsRowSection indentation:0], // Color Mapping
            [TSSettingsLayoutRow controls:@[@"settings.cSu-im-H1E"] kind:TSSettingsRowSection indentation:0], // Insertion Cursor
            [TSSettingsLayoutRow controls:@[@"settings.5ba-33-JZx"] kind:TSSettingsRowSection indentation:0], // Saving Documents
        ]],
        @"settings.g8D-eJ-1Uv": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.405"] kind:TSSettingsRowControls indentation:0], // imageCopyTypePopup
        ]],
        @"settings.N8d-Su-fXT": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.437"] kind:TSSettingsRowControls indentation:0], // colorMapButton
            [TSSettingsLayoutRow controls:@[@"settings.439", @"settings.434"] kind:TSSettingsRowControls indentation:1], // Foreground Prominence:
        ]],
        @"settings.C6J-2i-mg2": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.RVR-YO-Xhy"] kind:TSSettingsRowControls indentation:0], // autoSaveEnabledButton
            [TSSettingsLayoutRow controls:@[@"settings.N8r-9Y-N2R"] kind:TSSettingsRowControls indentation:1], // A macOS feature that overwrites the file automatically while you edit. Takes effect after TeXShop restarts.
            [TSSettingsLayoutRow controls:@[@"settings.jhC-up-cya"] kind:TSSettingsRowControls indentation:1], // keepBackupButton
            [TSSettingsLayoutRow controls:@[@"settings.5xa-en-KkV"] kind:TSSettingsRowControls indentation:0], // saveEncodingMenuButton
        ]],
        @"settings.ohZ-7S-ijU": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.RtB-ZN-uCk"] kind:TSSettingsRowControls indentation:0], // blockCursorButton
            [TSSettingsLayoutRow controls:@[@"settings.sHY-8y-Sax", @"settings.Wrg-WR-c6H"] kind:TSSettingsRowControls indentation:1], // Cursor Color:
            [TSSettingsLayoutRow controls:@[@"settings.QEw-MD-Er9", @"settings.l7y-UX-7WO"] kind:TSSettingsRowControls indentation:1], // Side of Insertion Line:
            [TSSettingsLayoutRow controls:@[@"settings.SWN-Un-R10", @"settings.uve-Zu-06Q"] kind:TSSettingsRowControls indentation:1], // Width for Left or Right:
        ]],
        @"settings.e2r-eO-p5f": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.Eb6-59-PxD"] kind:TSSettingsRowSection indentation:0], // Personal Script
            [TSSettingsLayoutRow controls:@[@"settings.DU3-gi-QzY"] kind:TSSettingsRowSection indentation:0], // XML Tag Choices
            [TSSettingsLayoutRow controls:@[@"settings.vEF-zd-SJl"] kind:TSSettingsRowSection indentation:0], // Alternate Engine
            [TSSettingsLayoutRow controls:@[@"settings.SS5-tZ-cDa"] kind:TSSettingsRowSection indentation:0], // pTeX support (for Japan)
            [TSSettingsLayoutRow controls:@[@"settings.03p-fB-1K3"] kind:TSSettingsRowSection indentation:0], // During File Save
            [TSSettingsLayoutRow controls:@[@"settings.Kin-Cw-xVc"] kind:TSSettingsRowSection indentation:0], // Project Root File
            [TSSettingsLayoutRow controls:@[@"settings.e3h-Wk-X7D"] kind:TSSettingsRowSection indentation:0], // Sparkle Updater
        ]],
        @"settings.CTJ-d3-TKI": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.sPQ-5E-qId"] kind:TSSettingsRowControls indentation:0], // convertUTFButton
        ]],
        @"settings.Lly-xe-Cer": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.UtV-tr-Xnu"] kind:TSSettingsRowControls indentation:0], // openRootFileButton
            [TSSettingsLayoutRow controls:@[@"settings.4J7-3F-0ja"] kind:TSSettingsRowControls indentation:0], // miniaturizeRootFileButton
        ]],
        @"settings.87n-8B-bOH": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.Tu2-Zu-ut5"] kind:TSSettingsRowControls indentation:0], // sparkleAutomaticButton
            [TSSettingsLayoutRow controls:@[@"settings.ssL-3D-6IR"] kind:TSSettingsRowControls indentation:1], // sparkleIntervalMatrix
        ]],
        @"settings.7EH-Vl-zSo": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.spX-dz-ROL"] kind:TSSettingsRowControls indentation:0], // ptexUtfOutputButton
        ]],
        @"settings.buj-8D-9FL": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.e8o-CH-MrS", @"settings.10b-du-keV"] kind:TSSettingsRowField indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.0GI-vh-5wv", @"settings.KBV-98-EKO"] kind:TSSettingsRowField indentation:0],
        ]],
        @"settings.Vy2-Hl-YOQ": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.ETt-2N-toX", @"settings.gZB-h1-n7P"] kind:TSSettingsRowField indentation:0],
        ]],
        @"settings.x37-2g-Y5J": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.Fww-AH-Uix", @"settings.J9Y-VM-xKk", @"settings.leH-sT-cbJ"] kind:TSSettingsRowControls indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.ct9-Gf-9nT", @"settings.ZIN-eZ-jRd", @"settings.pUb-HQ-m1i"] kind:TSSettingsRowControls indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.dNI-hB-T5a", @"settings.Ejc-g3-EPJ", @"settings.3T5-e8-Mcd"] kind:TSSettingsRowControls indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.F6b-YV-mvL", @"settings.9KW-ea-Zni"] kind:TSSettingsRowControls indentation:0],
        ]],
        @"settings.10": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.47"] kind:TSSettingsRowSection indentation:0], // Preview Window Position
            [TSSettingsLayoutRow controls:@[@"settings.329"] kind:TSSettingsRowSection indentation:0], // Default Page Style
            [TSSettingsLayoutRow controls:@[@"settings.342"] kind:TSSettingsRowSection indentation:0], // Magnification Method
            [TSSettingsLayoutRow controls:@[@"settings.501"] kind:TSSettingsRowSection indentation:0], // Two-Page Arrangement
            [TSSettingsLayoutRow controls:@[@"settings.111"] kind:TSSettingsRowSection indentation:0], // Zoom for new PDFs
            [TSSettingsLayoutRow controls:@[@"settings.330"] kind:TSSettingsRowSection indentation:0], // Default Mouse Mode
            [TSSettingsLayoutRow controls:@[@"settings.MEp-AF-AgT"] kind:TSSettingsRowSection indentation:0], // One Window Mode
            [TSSettingsLayoutRow controls:@[@"settings.555"] kind:TSSettingsRowSection indentation:0], // External Editor
            [TSSettingsLayoutRow controls:@[@"settings.YrC-m9-abH"] kind:TSSettingsRowSection indentation:0], // HTML Window Position
            [TSSettingsLayoutRow controls:@[@"settings.5HT-3x-Zr6"] kind:TSSettingsRowSection indentation:0], // Display
            [TSSettingsLayoutRow controls:@[@"settings.FSn-iA-3oc"] kind:TSSettingsRowSection indentation:0], // Opening Source and Preview
            [TSSettingsLayoutRow controls:@[@"settings.p2D-Mi-Gyc"] kind:TSSettingsRowSection indentation:0], // Home URL
        ]],
        @"settings.f5T-2e-wFm": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.44"] kind:TSSettingsRowControls indentation:0], // pdfWindowPosMatrix
            [TSSettingsLayoutRow controls:@[@"settings.46"] kind:TSSettingsRowControls indentation:1], // pdfWindowPosButton
        ]],
        @"settings.HSm-QY-Bs6": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.113", @"settings.116"] kind:TSSettingsRowControls indentation:0], // magTextField
        ]],
        @"settings.slE-Lh-2Zi": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.345"] kind:TSSettingsRowControls indentation:0], // mouseModePopup
        ]],
        @"settings.H13-e9-Oe5": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.334"] kind:TSSettingsRowControls indentation:0], // resizeOptionPopup
        ]],
        @"settings.NAj-yD-p0X": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.340"] kind:TSSettingsRowControls indentation:0], // pageStylePopup
        ]],
        @"settings.31B-Wt-psB": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.506"] kind:TSSettingsRowControls indentation:0], // firstPageMatrix
            [TSSettingsLayoutRow controls:@[@"settings.preview-cover-button"] kind:TSSettingsRowControls indentation:0], // displayAsBookButton
            [TSSettingsLayoutRow controls:@[@"settings.preview-cover-note"] kind:TSSettingsRowControls indentation:0], // Applies on opening. Magic comments and PDF reading direction take precedence.
        ]],
        @"settings.WGe-hF-bop": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.557"] kind:TSSettingsRowControls indentation:0], // autoPDFButton
        ]],
        @"settings.024-V2-dVf": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.preview-link-popups-button"] kind:TSSettingsRowControls indentation:0], // linkPopupsButton
            [TSSettingsLayoutRow controls:@[@"settings.preview-scroll-page-turn-button"] kind:TSSettingsRowControls indentation:0], // scrollPageTurnButton
        ]],
        @"settings.7Xo-ey-gfu": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.G6V-Sw-jFT"] kind:TSSettingsRowControls indentation:0], // useTwoWindowsButton
            [TSSettingsLayoutRow controls:@[@"settings.MBq-SG-G54"] kind:TSSettingsRowControls indentation:0], // useOneWindowButton
        ]],
        @"settings.9uo-ZA-WFK": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.iRm-g2-CpD"] kind:TSSettingsRowControls indentation:0], // useLeftSourceButton
            [TSSettingsLayoutRow controls:@[@"settings.zvK-4Q-HJ5"] kind:TSSettingsRowControls indentation:0], // useRightSourceButton
        ]],
        @"settings.wSg-RM-Nd0": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.4qx-Bg-9Ii"] kind:TSSettingsRowControls indentation:0], // htmlWindowPosMatrix
            [TSSettingsLayoutRow controls:@[@"settings.EPC-FR-GKh"] kind:TSSettingsRowControls indentation:1], // htmlWindowPosButton
        ]],
        @"settings.zbb-he-jOh": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.gxJ-rd-D1v"] kind:TSSettingsRowControls indentation:0], // HtmlHomeField
        ]],
        @"settings.11": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.14"] kind:TSSettingsRowSection indentation:0], // Document Font
            [TSSettingsLayoutRow controls:@[@"settings.262"] kind:TSSettingsRowSection indentation:0], // Encoding
            [TSSettingsLayoutRow controls:@[@"settings.585"] kind:TSSettingsRowSection indentation:0], // Find Panel (after restart)
            [TSSettingsLayoutRow controls:@[@"settings.19"] kind:TSSettingsRowSection indentation:0], // Source Window Position
            [TSSettingsLayoutRow controls:@[@"settings.ENd-QB-0Uf"] kind:TSSettingsRowSection indentation:0], // Dictionary
            [TSSettingsLayoutRow controls:@[@"settings.236"] kind:TSSettingsRowSection indentation:0], // On Startup
            [TSSettingsLayoutRow controls:@[@"settings.925"] kind:TSSettingsRowSection indentation:0], // Command Completion Triggered By:
            [TSSettingsLayoutRow controls:@[@"settings.kgx-Sa-LDF"] kind:TSSettingsRowSection indentation:0], // Spell Checking
            [TSSettingsLayoutRow controls:@[@"settings.934"] kind:TSSettingsRowSection indentation:0], // Parens Targets & Highlight Color
            [TSSettingsLayoutRow controls:@[@"settings.eIA-mh-q2u"] kind:TSSettingsRowSection indentation:0], // Line Number Size
            [TSSettingsLayoutRow controls:@[@"settings.aig-4m-gAG"] kind:TSSettingsRowSection indentation:0], // Open New Windows as Tabs
        ]],
        @"settings.Pu6-MU-aNn": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.926"] kind:TSSettingsRowControls indentation:0], // commandCompletionMatrix
        ]],
        @"settings.pUE-4T-xRQ": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.16", @"settings.18"] kind:TSSettingsRowControls indentation:0], // Set ...
        ]],
        @"settings.3z0-MM-qNs": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.30"] kind:TSSettingsRowControls indentation:0], // sourceWindowPosMatrix
            [TSSettingsLayoutRow controls:@[@"settings.33"] kind:TSSettingsRowControls indentation:1], // docWindowPosButton
        ]],
        @"settings.9of-71-LXe": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.238"] kind:TSSettingsRowControls indentation:0], // openEmptyButton
            [TSSettingsLayoutRow controls:@[@"settings.272"] kind:TSSettingsRowControls indentation:0], // externalEditorButton
        ]],
        @"settings.3LN-k2-0k6": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.949", @"settings.948", @"settings.947", @"settings.946"] kind:TSSettingsRowControls indentation:0], // checkBraceButton
        ]],
        @"settings.o5n-nj-mAS": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.278"] kind:TSSettingsRowControls indentation:0], // defaultEncodeMatrix
        ]],
        @"settings.ldk-MN-KjH": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.o1v-YF-ekd"] kind:TSSettingsRowControls indentation:0], // dictionaryPopup
        ]],
        @"settings.nKk-Hj-6Xi": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.ts-aware-spelling"] kind:TSSettingsRowControls indentation:0], // texAwareSpellCheckButton
            [TSSettingsLayoutRow controls:@[@"settings.ts-edit-spelling"] kind:TSSettingsRowControls indentation:1], // editSpellingExclusionsButton
            [TSSettingsLayoutRow controls:@[@"settings.cp7-bc-avh"] kind:TSSettingsRowControls indentation:0], // Switch
        ]],
        @"settings.M4W-gm-CJz": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.581"] kind:TSSettingsRowControls indentation:0], // findMatrix
        ]],
        @"settings.Ri9-vJ-bJO": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.M7m-FU-qKi"] kind:TSSettingsRowControls indentation:0], // openAsTabsMatrix
        ]],
        @"settings.QiF-2c-EEp": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.yo8-RP-pZK"] kind:TSSettingsRowControls indentation:0], // lineSizeMatrix
        ]],
        @"settings.aT1-LS-7Yk": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.JhE-OB-yPt", @"settings.5ZN-yj-GI3"] kind:TSSettingsRowField indentation:0], // Title:
            [TSSettingsLayoutRow controls:@[@"settings.fck-0B-Qsq", @"settings.N2G-gi-llW"] kind:TSSettingsRowControls indentation:0], // Cancel
        ]],
        @"settings.ZlV-mI-DdK": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.7hF-dm-sw0"] kind:TSSettingsRowSection indentation:0], // Themes
            [TSSettingsLayoutRow controls:@[@"settings.ycd-ZH-bzw"] kind:TSSettingsRowSection indentation:0], // Actions
            [TSSettingsLayoutRow controls:@[@"settings.qWb-pL-mS9"] kind:TSSettingsRowSection indentation:0],
        ]],
        @"settings.BGc-hx-w5D": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.cy6-ep-C9P", @"settings.xpQ-zQ-oZe"] kind:TSSettingsRowField indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.zWc-ak-WM8", @"settings.eo2-De-DNv"] kind:TSSettingsRowField indentation:0],
            [TSSettingsLayoutRow controls:@[@"settings.FOl-CH-y3R", @"settings.O5R-pm-csa"] kind:TSSettingsRowField indentation:0],
        ]],
        @"settings.RA7-3r-O6n": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.8bu-du-vzc"] kind:TSSettingsRowControls indentation:0], // Create New Theme
            [TSSettingsLayoutRow controls:@[@"settings.uXA-S0-9dP"] kind:TSSettingsRowControls indentation:0], // New Theme from Settings
        ]],
        @"settings.3cH-6c-fhq": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.S3x-qU-RUF"] kind:TSSettingsRowSection indentation:0],
        ]],
        @"settings.Vrr-bl-kF2": [TSSettingsLayoutGroup grid:@[
            @[@"", @"settings.Zhi-Nc-sIA", @"settings.Xkl-nX-sSN", @"settings.ae7-a9-Qgg"],
            @[@"settings.uoe-u2-eTF", @"settings.L8Q-Ov-EVr", @"settings.0fE-JX-Dl8", @"settings.2U5-cN-QJw"],
            @[@"settings.AjW-wj-jex", @"settings.Kx3-n3-dsv", @"settings.ooP-O9-ggT", @"settings.c9R-58-ggg"],
            @[@"settings.Lll-R4-I4e", @"settings.FoL-zy-obh", @"settings.GBU-aF-4Dc", @""],
            @[@"settings.Kmh-HA-3xm", @"", @"settings.hCM-4U-XkM", @"settings.cnt-Xt-iQF"],
            @[@"", @"settings.f7c-Uy-IWR", @"settings.26f-IM-YOw", @""],
            @[@"settings.2pA-Xa-68E", @"settings.Rp9-1a-atr", @"settings.fIc-C1-M6K", @""],
            @[@"", @"settings.su8-Oy-JXz", @"settings.yqp-3h-Xoo", @"settings.eY1-yZ-vok"],
            @[@"settings.tc1-e0-xgJ", @"settings.fFa-bR-0xj", @"settings.4y8-qP-NW7", @"settings.AFk-AJ-HpM"],
            @[@"", @"settings.XCe-dk-8wN", @"settings.fPb-tq-v7n", @"settings.Hux-Cw-jA3"],
            @[@"", @"settings.5JB-rw-aya", @"settings.iE0-it-g4Y", @"settings.QyC-Pf-rbS"],
            @[@"", @"settings.90q-I8-KiD", @"settings.kGY-aO-HYV", @""],
            @[@"settings.88k-zC-g06", @"settings.2Dt-EA-nXb", @"settings.aI6-Dw-QYc", @""],
            @[@"", @"settings.77O-2c-Lxj", @"settings.cMB-8z-NF6", @""],
            @[@"settings.IrI-im-tKy", @"settings.lN2-X9-deG", @"settings.XS9-49-mQR", @""],
            @[@"", @"settings.jAj-Fp-hqd", @"settings.6CN-Fj-kr5", @"settings.nWQ-m2-MZf"],
            @[@"settings.EgD-4a-cyP", @"settings.fwl-6S-zne", @"settings.GcO-ys-oEm", @"settings.SG4-BQ-aGU"],
            @[@"", @"settings.tPl-K1-TUE", @"settings.oZu-II-zIi", @""],
            @[@"", @"settings.0Uo-lK-RFI", @"settings.et7-Ed-flT", @""],
            @[@"", @"settings.b16-L9-MGQ", @"settings.Kue-aK-2xf", @"settings.ei5-oS-XfZ"],
            @[@"settings.tDp-OY-PiU", @"settings.pp5-6n-eid", @"settings.w0t-xC-91b", @"settings.88L-Tw-ww4"],
            @[@"", @"settings.0me-ja-I3a", @"settings.UKr-GF-nnj", @""],
            @[@"", @"settings.N5y-1z-ygl", @"settings.UIf-La-lmG", @""],
        ]],
        @"settings.PTb-79-UFr": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.mRX-2g-H6p"] kind:TSSettingsRowSection indentation:0],
        ]],
        @"settings.Miy-Mb-Gjy": [TSSettingsLayoutGroup grid:@[
            @[@"", @"settings.XUy-wS-6Ax", @"settings.4OO-ZY-xEQ", @"settings.5od-zc-vUi"],
            @[@"settings.ASZ-vu-AQM", @"settings.oFu-vs-I7z", @"settings.Ipf-Me-hES", @"settings.rRX-aG-rEU"],
            @[@"", @"settings.7io-tP-qCI", @"settings.rM7-kB-IC1", @"settings.Yfv-ST-bQG"],
            @[@"", @"settings.Kg3-7E-zxe", @"settings.WkN-TZ-ZV7", @"settings.lZA-UQ-g4b"],
            @[@"", @"settings.j3L-3N-nni", @"", @""],
            @[@"", @"settings.cxQ-mH-uhG", @"", @""],
            @[@"", @"settings.rB4-mR-LTa", @"settings.Xj7-X1-bbY", @"settings.nWg-0k-sk7"],
            @[@"settings.zPQ-Ry-gvz", @"settings.dMn-ER-oAY", @"settings.AU4-OU-59f", @"settings.aWA-sd-k8E"],
        ]],
        @"settings.170": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.675"] kind:TSSettingsRowSection indentation:0], // After Typesetting
            [TSSettingsLayoutRow controls:@[@"settings.183"] kind:TSSettingsRowSection indentation:0], // Default Command
            [TSSettingsLayoutRow controls:@[@"settings.314"] kind:TSSettingsRowSection indentation:0], // During File Save
            [TSSettingsLayoutRow controls:@[@"settings.188"] kind:TSSettingsRowSection indentation:0], // Default Script
            [TSSettingsLayoutRow controls:@[@"settings.823"] kind:TSSettingsRowSection indentation:0], // Sync Method
            [TSSettingsLayoutRow controls:@[@"settings.163-F5-v8Z"] kind:TSSettingsRowSection indentation:0], // Ghostscript Options
            [TSSettingsLayoutRow controls:@[@"settings.W5U-9S-4OG"] kind:TSSettingsRowSection indentation:0], // If Sync Opens a New Window
        ]],
        @"settings.mpr-dj-yHz": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.186"] kind:TSSettingsRowControls indentation:0], // defaultScriptMatrix
        ]],
        @"settings.ArE-cZ-tBv": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.316"] kind:TSSettingsRowControls indentation:0], // saveRelatedButton
        ]],
        @"settings.Hkv-Rw-Dgs": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.678"] kind:TSSettingsRowControls indentation:0], // afterTypesettingMatrix
        ]],
        @"settings.2rk-I1-3zq": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.782"] kind:TSSettingsRowControls indentation:0], // syncMatrix
        ]],
        @"settings.vSL-XM-z8W": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.181"] kind:TSSettingsRowControls indentation:0], // defaultCommandMatrix
            [TSSettingsLayoutRow controls:@[@"settings.592"] kind:TSSettingsRowControls indentation:1], // engineTextField
        ]],
        @"settings.0et-QV-IOa": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.odf-Ny-S9G"] kind:TSSettingsRowControls indentation:0], // syncTabButton
            [TSSettingsLayoutRow controls:@[@"settings.5Py-bW-sDC"] kind:TSSettingsRowControls indentation:0], // (Should be OFF for most users.)
        ]],
        @"settings.XzI-12-6dm": [TSSettingsLayoutGroup rows:@[
            [TSSettingsLayoutRow controls:@[@"settings.8pA-l1-G9L"] kind:TSSettingsRowControls indentation:0], // useTransparencyButton
        ]],
    };
}
