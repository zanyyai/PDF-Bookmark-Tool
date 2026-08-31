#Requires AutoHotkey v2.0
#SingleInstance Force

IniPath := A_ScriptDir . "\rules_history.ini"

MainGui := Gui("+Resize", "PDF 智能书签写入工具 (JSON 存储与强力防重版)")

; 1. 文件选择区
MainGui.Add("Text", "x10 y15 w70 h20", "PDF 文件:")
EditPdfPath := MainGui.Add("Edit", "x80 y12 w290 h20", "")
LinkOpenDir := MainGui.Add("Link", "x380 y15 w85 h20", '<a id="open_dir">打开所在文件夹</a>')
BtnBrowse := MainGui.Add("Button", "x470 y10 w80 h24", "浏览...")

; 2. 页码偏移量
MainGui.Add("Text", "x10 y45 w80 h20", "页码偏移:")
EditOffset := MainGui.Add("Edit", "x80 y42 w60 h20", "0")
MainGui.Add("Text", "x150 y45 w390 h20", "(PDF实际页码 = 目录印刷页码 + 偏移量，支持负数)")

; 3. 多级正则匹配规则配置区
MainGui.Add("GroupBox", "x10 y70 w540 h150", "多级书签匹配规则配置 (可下拉选择历史规则)")

MainGui.Add("Text", "x20 y92 w70 h20", "一级书签:")
CboxRegexL1 := MainGui.Add("ComboBox", "x90 y89 w170 h150", ["^[一二三四五六七八九十]+[、\.]"])
CboxRegexL1.Text := "^[一二三四五六七八九十]+[、\.]"

MainGui.Add("Text", "x270 y92 w70 h20", "二级书签:")
CboxRegexL2 := MainGui.Add("ComboBox", "x340 y89 w200 h150", ["^【.*】"])
CboxRegexL2.Text := "^【.*】"

MainGui.Add("Text", "x20 y122 w70 h20", "三级书签:")
CboxRegexL3 := MainGui.Add("ComboBox", "x90 y119 w170 h150", ["^\d+\.\s*"])
CboxRegexL3.Text := "^\d+\.\s*"

MainGui.Add("Text", "x270 y122 w70 h20", "行匹配:")
CboxRegexLine := MainGui.Add("ComboBox", "x340 y119 w200 h150", ["\d+\s*页?\s*$"])
CboxRegexLine.Text := "\d+\s*页?\s*$"

MainGui.Add("Text", "x20 y152 w70 h20", "底级书签:")
CboxRegexTitle := MainGui.Add("ComboBox", "x90 y149 w170 h150", ["^(.*?)(?=\s*[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$)"])
CboxRegexTitle.Text := "^(.*?)(?=\s*[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$)"

MainGui.Add("Text", "x270 y152 w70 h20", "页码提取:")
CboxRegexPage := MainGui.Add("ComboBox", "x340 y149 w200 h150", ["(\d+)\s*页?\s*$"])
CboxRegexPage.Text := "(\d+)\s*页?\s*$"

MainGui.Add("Text", "x20 y185 w520 h20", "💡 说明：下拉可切换历史规则。写入成功后，新规则将以示例样本命名自动保存。")

; 4. 文本粘贴区
MainGui.Add("Text", "x10 y225 w200 h20", "请粘贴目录文本:")
EditInputText := MainGui.Add("Edit", "x10 y245 w540 h100 +Multi +WantReturn +VScroll", "")

; 5. 解析预览按钮
BtnParse := MainGui.Add("Button", "x10 y352 w120 h28", "解析预览")

; 6. 预览表格
LV := MainGui.Add("ListView", "x10 y385 w540 h150 Grid AltSubmit", ["序号", "层级", "书签标题", "目标页码"])
LV.ModifyCol(1, 45)
LV.ModifyCol(2, 45)
LV.ModifyCol(3, 360)
LV.ModifyCol(4, 70)

; 7. 执行按钮
BtnInsert := MainGui.Add("Button", "x10 y542 w540 h35", "🚀 一键写入目录书签到 PDF")

; 全局变量：记录解析时各项捕获到的首个样本名称
Global FirstMatches := Map("L1", "", "L2", "", "L3", "", "Line", "", "Title", "", "Page", "")

; 事件绑定
BtnBrowse.OnEvent("Click", (*) => BrowsePDF())
BtnParse.OnEvent("Click", (*) => ParseTextToLV())
BtnInsert.OnEvent("Click", (*) => WriteToPDF())
EditOffset.OnEvent("Change", (*) => AutoRefreshLV())
LinkOpenDir.OnEvent("Click", (*) => OpenPdfFolder())
EditPdfPath.OnEvent("Change", (*) => SaveLastPdfPath(EditPdfPath.Value))

; 初始化：读取历史规则 & 恢复上次选择的 PDF 路径
LoadHistoryToComboBoxes()
LoadLastPdfPath()

MainGui.Show("w560 h585")

BrowsePDF() {
    SelectedFile := FileSelect(3, , "选择 PDF 文件", "PDF 文件 (*.pdf)")
    if (SelectedFile != "") {
        EditPdfPath.Value := SelectedFile
        SaveLastPdfPath(SelectedFile)
    }
}

OpenPdfFolder() {
    PdfPath := EditPdfPath.Value
    if (PdfPath == "") {
        MsgBox("请先选择 PDF 文件！", "提示", 48)
        return
    }
    
    if FileExist(PdfPath) {
        Run('explorer.exe /select,"' . PdfPath . '"')
    } else {
        SplitPath(PdfPath, , &fdir)
        if (fdir != "" && DirExist(fdir)) {
            Run(fdir)
        } else {
            MsgBox("找不到该 PDF 文件或其所在目录！", "错误", 16)
        }
    }
}

SaveLastPdfPath(path) {
    if (path != "" && FileExist(path)) {
        IniWrite(path, IniPath, "Config", "LastPdfPath")
    }
}

LoadLastPdfPath() {
    if FileExist(IniPath) {
        try {
            lastPath := IniRead(IniPath, "Config", "LastPdfPath", "")
            if (lastPath != "" && FileExist(lastPath)) {
                EditPdfPath.Value := lastPath
            }
        }
    }
}

AutoRefreshLV() {
    if (Trim(EditInputText.Value) != "" && LV.GetCount() > 0) {
        ParseTextToLV()
    }
}

GetOffsetValue() {
    rawStr := Trim(EditOffset.Value)
    if (rawStr == "" || rawStr == "-")
        return 0
    if RegExMatch(rawStr, "^-?\d+$")
        return Integer(rawStr)
    return 0
}

; 从 ComboBox 中剥离开头的 [样本名] 标注，还原纯正则表达式
GetCleanRegex(cboxObj) {
    rawVal := Trim(cboxObj.Text)
    if (rawVal == "")
        return ""
    
    while RegExMatch(rawVal, "^\[.*?\]\s*(.*)$", &m) {
        rawVal := Trim(m[1])
    }
    
    return rawVal
}

; 核心解析逻辑（带 try-catch 安全防崩）
ParseTextToLV() {
    rawText := EditInputText.Value
    if (Trim(rawText) == "") {
        MsgBox("请先粘贴文本！", "提示", 48)
        return
    }

    Global FirstMatches := Map("L1", "", "L2", "", "L3", "", "Line", "", "Title", "", "Page", "")

    regL1 := GetCleanRegex(CboxRegexL1)
    regL2 := GetCleanRegex(CboxRegexL2)
    regL3 := GetCleanRegex(CboxRegexL3)
    regLine := GetCleanRegex(CboxRegexLine)
    regTitle := GetCleanRegex(CboxRegexTitle)
    regPage := GetCleanRegex(CboxRegexPage)
    
    offset := GetOffsetValue()

    LV.Delete()
    
    cleanText := StrReplace(rawText, "`r`n", "`n")
    cleanText := StrReplace(cleanText, "`r", "`n")
    lines := StrSplit(cleanText, "`n")

    parsedItems := []
    activeL1 := ""
    activeL2 := ""
    activeL3 := ""

    for line in lines {
        lineStr := Trim(line)
        if (lineStr == "")
            continue

        linePage := 0
        if (regPage != "" && IsRegMatchSafe(lineStr, regPage, &mPage)) {
            linePage := Integer(mPage[1] != "" ? mPage[1] : mPage[0])
            if (FirstMatches["Page"] == "")
                FirstMatches["Page"] := "页码样本:" . linePage
        }

        if (regL1 != "" && IsRegMatchSafe(lineStr, regL1)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL1 := Trim(cleanTitle)
            activeL2 := ""
            activeL3 := ""
            
            if (FirstMatches["L1"] == "")
                FirstMatches["L1"] := activeL1

            parsedItems.Push(Map("type", "HEADER", "title", activeL1, "page", linePage, "level", 1))
            continue
        }

        if (regL2 != "" && IsRegMatchSafe(lineStr, regL2)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL2 := Trim(cleanTitle)
            activeL3 := ""
            
            if (FirstMatches["L2"] == "")
                FirstMatches["L2"] := activeL2

            lvl := (activeL1 != "" ? 1 : 0) + 1
            parsedItems.Push(Map("type", "HEADER", "title", activeL2, "page", linePage, "level", lvl))
            continue
        }

        if (regL3 != "" && IsRegMatchSafe(lineStr, regL3)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL3 := Trim(cleanTitle)
            
            if (FirstMatches["L3"] == "")
                FirstMatches["L3"] := activeL3

            lvl := (activeL1 != "" ? 1 : 0) + (activeL2 != "" ? 1 : 0) + 1
            parsedItems.Push(Map("type", "HEADER", "title", activeL3, "page", linePage, "level", lvl))
            continue
        }

        isMatchLine := (regLine == "" || IsRegMatchSafe(lineStr, regLine))
        if (isMatchLine && linePage > 0) {
            if (FirstMatches["Line"] == "" && regLine != "")
                FirstMatches["Line"] := "匹配行:" . SubStr(lineStr, 1, 15)

            titleStr := lineStr
            if (regTitle != "" && IsRegMatchSafe(lineStr, regTitle, &mTitle)) {
                titleStr := Trim(mTitle[1] != "" ? mTitle[1] : mTitle[0])
            }
            cleanTitle := RegExReplace(titleStr, "^[\s\t*★]+", "")

            if (FirstMatches["Title"] == "")
                FirstMatches["Title"] := cleanTitle

            parentCount := (activeL1 != "" ? 1 : 0) + (activeL2 != "" ? 1 : 0) + (activeL3 != "" ? 1 : 0)
            leafLvl := parentCount + 1

            parsedItems.Push(Map("type", "LEAF", "title", cleanTitle, "page", linePage, "level", leafLvl))
        }
    }

    Loop parsedItems.Length {
        idx := A_Index
        item := parsedItems[idx]
        if (item["page"] == 0) {
            foundPage := 1
            Loop (parsedItems.Length - idx) {
                subItem := parsedItems[idx + A_Index]
                if (subItem["page"] > 0) {
                    foundPage := subItem["page"]
                    break
                }
            }
            item["page"] := foundPage
        }
    }

    Index := 1
    for item in parsedItems {
        finalPage := item["page"] + offset
        if (finalPage < 1)
            finalPage := 1
        LV.Add("", Index, item["level"], item["title"], finalPage)
        Index++
    }

    if (LV.GetCount() == 0) {
        MsgBox("解析完成，未找到符合条件的书签项！", "提示", 48)
    }
}

; 安全正则匹配包裹函数
IsRegMatchSafe(haystack, needle, &matchObj := "") {
    if (needle == "")
        return false
    try {
        return RegExMatch(haystack, needle, &matchObj)
    } catch {
        return false
    }
}

WriteToPDF() {
    PdfPath := EditPdfPath.Value
    if (!FileExist(PdfPath)) {
        MsgBox("请选择有效的 PDF 文件！", "警告", 48)
        return
    }
    
    if (Trim(EditInputText.Value) != "") {
        ParseTextToLV()
    }

    if (LV.GetCount() == 0) {
        MsgBox("列表中没有可写入的书签项！", "错误", 16)
        return
    }

    SplitPath(PdfPath, &fname, &fdir, &fext, &fname_no_ext)
    outputPath := fdir "\" fname_no_ext "_带书签.pdf"

    toc := []
    Loop LV.GetCount() {
        lvl := Integer(LV.GetText(A_Index, 2))
        title := LV.GetText(A_Index, 3)
        page := Integer(LV.GetText(A_Index, 4))
        toc.Push(Map("level", lvl, "title", title, "page", page))
    }

    params := Map("pdf", PdfPath, "toc", toc, "output", outputPath)
    jsonStr := MapToJson(params)

    tmpJsonPath := A_ScriptDir . "\_temp_toc_data.json"

    if FileExist(tmpJsonPath)
        FileDelete(tmpJsonPath)
    FileAppend(jsonStr, tmpJsonPath, "UTF-8-RAW")

    cmd := 'python "' . A_ScriptDir . '\pdf_engine_Lite.py" "' . tmpJsonPath . '"'
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(cmd)
    res := exec.StdOut.ReadAll()

    if FileExist(tmpJsonPath)
        FileDelete(tmpJsonPath)

    if InStr(res, "success") {
        SaveRulesToHistory()
        LoadHistoryToComboBoxes()
        SaveLastPdfPath(PdfPath)
        
        MsgBox("书签写入成功！文件保存在：`n" . outputPath, "成功", 64)
        Run(outputPath)
    } else {
        MsgBox("写入失败：" . res, "错误", 16)
    }
}

; 使用 JSON 存入 INI 历史文件 (彻底解决转义与分隔符冲突)
SaveRulesToHistory() {
    categories := [
        Map("section", "RegexL1", "cbox", CboxRegexL1, "sample", FirstMatches["L1"]),
        Map("section", "RegexL2", "cbox", CboxRegexL2, "sample", FirstMatches["L2"]),
        Map("section", "RegexL3", "cbox", CboxRegexL3, "sample", FirstMatches["L3"]),
        Map("section", "RegexLine", "cbox", CboxRegexLine, "sample", FirstMatches["Line"]),
        Map("section", "RegexTitle", "cbox", CboxRegexTitle, "sample", FirstMatches["Title"]),
        Map("section", "RegexPage", "cbox", CboxRegexPage, "sample", FirstMatches["Page"])
    ]

    timeStr := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    rawIniContent := FileExist(IniPath) ? FileRead(IniPath, "UTF-8") : ""

    for cat in categories {
        regVal := GetCleanRegex(cat["cbox"])
        sampleText := Trim(cat["sample"])

        ; 未成功匹配任何样本不存入
        if (regVal == "" || sampleText == "")
            continue

        section := cat["section"]
        isExist := false
        keyCount := 1

        inTargetSection := false
        Loop Parse, rawIniContent, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line == "")
                continue

            if RegExMatch(line, "^\[(.*?)\]$", &mSec) {
                inTargetSection := (mSec[1] == section)
                continue
            }

            if (inTargetSection) {
                keyCount++
                eqPos := InStr(line, "=")
                if (eqPos > 0) {
                    valJson := SubStr(line, eqPos + 1)
                    if RegExMatch(valJson, '"regex":\s*"(.*?)"', &mReg) {
                        savedRegex := UnescapeJsonStr(mReg[1])
                        if (savedRegex == regVal) {
                            isExist := true
                            break
                        }
                    }
                }
            }
        }

        if (!isExist) {
            sampleName := SubStr(sampleText, 1, 20)
            ruleMap := Map("time", timeStr, "name", sampleName, "regex", regVal)
            jsonVal := MapToJson(ruleMap)
            IniWrite(jsonVal, IniPath, section, "rule_" . keyCount)
        }
    }
}

; 解析 INI 里的 JSON 历史数据并刷入 ComboBox
LoadHistoryToComboBoxes() {
    if (!FileExist(IniPath))
        return

    mapping := Map(
        "RegexL1", CboxRegexL1,
        "RegexL2", CboxRegexL2,
        "RegexL3", CboxRegexL3,
        "RegexLine", CboxRegexLine,
        "RegexTitle", CboxRegexTitle,
        "RegexPage", CboxRegexPage
    )

    for section, cbox in mapping {
        try {
            secContent := IniRead(IniPath, section)
            list := []
            Loop Parse, secContent, "`n", "`r" {
                line := Trim(A_LoopField)
                if (line == "")
                    continue
                
                eqPos := InStr(line, "=")
                if (eqPos > 0) {
                    jsonStr := SubStr(line, eqPos + 1)
                    
                    ; 正则提取 JSON 字段
                    nameVal := ""
                    regexVal := ""
                    if RegExMatch(jsonStr, '"name":\s*"(.*?)"', &mName)
                        nameVal := UnescapeJsonStr(mName[1])
                    if RegExMatch(jsonStr, '"regex":\s*"(.*?)"', &mRegex)
                        regexVal := UnescapeJsonStr(mRegex[1])
                    
                    if (regexVal != "") {
                        displayStr := (nameVal != "") ? "[" . nameVal . "] " . regexVal : regexVal
                        list.Push(displayStr)
                    }
                }
            }
            if (list.Length > 0) {
                currentVal := cbox.Text
                cbox.Delete()
                cbox.Add(list)
                cbox.Choose(0) ; 清除锁定的编辑状态，唤醒 IME 输入法
                cbox.Text := currentVal
            }
        }
    }
}

; 安全反转义 JSON 内部转义字符串
UnescapeJsonStr(str) {
    str := StrReplace(str, '\"', '"')
    str := StrReplace(str, '\\', '\')
    str := StrReplace(str, '\/', '/')
    str := StrReplace(str, '\b', '`b')
    str := StrReplace(str, '\f', '`f')
    str := StrReplace(str, '\n', '`n')
    str := StrReplace(str, '\r', '`r')
    str := StrReplace(str, '\t', '`t')
    return str
}

MapToJson(obj) {
    if Type(obj) != "Map" && Type(obj) != "Array"
        return '"' . CleanJsonString(String(obj)) . '"'
    
    isArr := (Type(obj) == "Array")
    str := isArr ? "[" : "{"
    
    for k, v in obj {
        key := isArr ? "" : '"' . CleanJsonString(String(k)) . '":'
        if (Type(v) == "Map" || Type(v) == "Array") {
            str .= key . MapToJson(v) . ","
        } else if IsNumber(v) {
            str .= key . v . ","
        } else {
            str .= key . '"' . CleanJsonString(String(v)) . '",'
        }
    }
    return RTrim(str, ",") . (isArr ? "]" : "}")
}

CleanJsonString(str) {
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, '"', '\"')
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`t", "\t")
    
    cleanStr := ""
    Loop Parse, str {
        code := Ord(A_LoopField)
        if (code >= 32) {
            cleanStr .= A_LoopField
        }
    }
    return cleanStr
}