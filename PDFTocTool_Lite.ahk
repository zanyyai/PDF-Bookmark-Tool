#Requires AutoHotkey v2.0
#SingleInstance Force

IniPath := A_ScriptDir . "\rules_history.ini"

MainGui := Gui("+Resize", "PDF 智能书签写入工具 (历史规则增强版)")

; 1. 文件选择
MainGui.Add("Text", "x10 y15 w70 h20", "PDF 文件:")
EditPdfPath := MainGui.Add("Edit", "x80 y12 w380 h20", "")
BtnBrowse := MainGui.Add("Button", "x470 y10 w80 h24", "浏览...")

; 2. 页码偏移量
MainGui.Add("Text", "x10 y45 w80 h20", "页码偏移:")
EditOffset := MainGui.Add("Edit", "x80 y42 w60 h20", "0")
MainGui.Add("Text", "x150 y45 w390 h20", "(PDF实际页码 = 目录印刷页码 + 偏移量，支持负数)")

; 3. 多级正则匹配规则配置区 (改用 ComboBox 下拉选择框)
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

; 初始化时加载 INI 历史规则到下拉框
LoadHistoryToComboBoxes()

MainGui.Show("w560 h585")

BrowsePDF() {
    SelectedFile := FileSelect(3, , "选择 PDF 文件", "PDF 文件 (*.pdf)")
    if (SelectedFile != "")
        EditPdfPath.Value := SelectedFile
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

; 从 UI 的 ComboBox 提取当前正则（去除下拉菜单展示的辅助前缀）
GetCleanRegex(cboxObj) {
    rawVal := cboxObj.Text
    ; 修复：移除了 &m 后面多余的一个右括号
    if RegExMatch(rawVal, "^\[(.*?)\]\s*(.*)$", &m) {
        return m[2]
    }
    return rawVal
}

ParseTextToLV() {
    rawText := EditInputText.Value
    if (Trim(rawText) == "") {
        MsgBox("请先粘贴文本！", "提示", 48)
        return
    }

    ; 清空历史样本记录
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
        if (regPage != "" && RegExMatch(lineStr, regPage, &mPage)) {
            linePage := Integer(mPage[1] != "" ? mPage[1] : mPage[0])
            if (FirstMatches["Page"] == "")
                FirstMatches["Page"] := "样本:" . linePage
        }

        ; 1. 一级高级书签
        if (regL1 != "" && RegExMatch(lineStr, regL1)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL1 := Trim(cleanTitle)
            activeL2 := ""
            activeL3 := ""
            
            if (FirstMatches["L1"] == "")
                FirstMatches["L1"] := activeL1

            item := Map("type", "HEADER", "title", activeL1, "page", linePage, "level", 1)
            parsedItems.Push(item)
            continue
        }

        ; 2. 二级高级书签
        if (regL2 != "" && RegExMatch(lineStr, regL2)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL2 := Trim(cleanTitle)
            activeL3 := ""
            
            if (FirstMatches["L2"] == "")
                FirstMatches["L2"] := activeL2

            lvl := (activeL1 != "" ? 1 : 0) + 1
            item := Map("type", "HEADER", "title", activeL2, "page", linePage, "level", lvl)
            parsedItems.Push(item)
            continue
        }

        ; 3. 三级高级书签
        if (regL3 != "" && RegExMatch(lineStr, regL3)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL3 := Trim(cleanTitle)
            
            if (FirstMatches["L3"] == "")
                FirstMatches["L3"] := activeL3

            lvl := (activeL1 != "" ? 1 : 0) + (activeL2 != "" ? 1 : 0) + 1
            item := Map("type", "HEADER", "title", activeL3, "page", linePage, "level", lvl)
            parsedItems.Push(item)
            continue
        }

        ; 4. 底级书签
        isMatchLine := (regLine == "" || RegExMatch(lineStr, regLine))
        if (isMatchLine && linePage > 0) {
            if (FirstMatches["Line"] == "" && regLine != "")
                FirstMatches["Line"] := "匹配行:" . SubStr(lineStr, 1, 15)

            titleStr := lineStr
            if (regTitle != "" && RegExMatch(lineStr, regTitle, &mTitle)) {
                titleStr := Trim(mTitle[1] != "" ? mTitle[1] : mTitle[0])
            }
            cleanTitle := RegExReplace(titleStr, "^[\s\t*★]+", "")

            if (FirstMatches["Title"] == "")
                FirstMatches["Title"] := cleanTitle

            parentCount := (activeL1 != "" ? 1 : 0) + (activeL2 != "" ? 1 : 0) + (activeL3 != "" ? 1 : 0)
            leafLvl := parentCount + 1

            item := Map("type", "LEAF", "title", cleanTitle, "page", linePage, "level", leafLvl)
            parsedItems.Push(item)
        }
    }

    ; 补全无页码的高级书签
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

    ; 渲染 ListView
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

    ; 1. 定义临时文件路径
    tmpJsonPath := A_ScriptDir . "\_temp_toc_data.json"

    ; 2. 写入 JSON 数据 (修改点：使用 "UTF-8-RAW" 避免写入 BOM)
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
        ; =============== 执行写入成功后，对规则进行历史保存 ===============
        SaveRulesToHistory()
        LoadHistoryToComboBoxes() ; 动态刷新下拉菜单
        
        MsgBox("书签写入成功！文件保存在：`n" . outputPath, "成功", 64)
        Run(outputPath)
    } else {
        MsgBox("写入失败：" . res, "错误", 16)
    }
}

; 保存规则至 INI 文件（含防重逻辑）
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

    for cat in categories {
        regVal := GetCleanRegex(cat["cbox"])
        if (Trim(regVal) == "")
            continue

        section := cat["section"]
        
        ; 检查是否已存在相同规则（防重）
        isExist := false
        try {
            iniSectionText := IniRead(IniPath, section)
            Loop Parse, iniSectionText, "`n", "`r" {
                if (A_LoopField == "")
                    continue
                parts := StrSplit(A_LoopField, "=")
                if (parts.Length >= 2) {
                    valPart := parts[2]
                    ; 抽取配置文件中的实际正则表达式
                    if InStr(valPart, "|") {
                        subParts := StrSplit(valPart, "|")
                        savedRegex := Trim(subParts[subParts.Length])
                    } else {
                        savedRegex := Trim(valPart)
                    }
                    if (savedRegex == regVal) {
                        isExist := true
                        break
                    }
                }
            }
        }

        ; 如果规则不存在，则新增存入 INI 文件
        if (!isExist) {
            sampleName := (cat["sample"] != "") ? SubStr(cat["sample"], 1, 20) : "未命名规则"
            ; 计算递增 key (rule_1, rule_2 ...)
            keyCount := 1
            try {
                secContent := IniRead(IniPath, section)
                for line in StrSplit(secContent, "`n") {
                    if (Trim(line) != "")
                        keyCount++
                }
            }
            
            ruleEntry := timeStr . " | " . sampleName . " | " . regVal
            IniWrite(ruleEntry, IniPath, section, "rule_" . keyCount)
        }
    }
}

; 从 INI 文件中读取历史规则装载到下拉菜单 (ComboBox) 中
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
                if (A_LoopField == "")
                    continue
                parts := StrSplit(A_LoopField, "=")
                if (parts.Length >= 2) {
                    valStr := parts[2]
                    if InStr(valStr, "|") {
                        subParts := StrSplit(valStr, "|")
                        ruleName := Trim(subParts[2])
                        ruleRegex := Trim(subParts[3])
                        displayStr := "[" . ruleName . "] " . ruleRegex
                    } else {
                        displayStr := Trim(valStr)
                    }
                    list.Push(displayStr)
                }
            }
            if (list.Length > 0) {
                currentVal := cbox.Text
                cbox.Delete()
                cbox.Add(list)
                cbox.Text := currentVal
            }
        }
    }
}

MapToJson(obj) {
    if Type(obj) != "Map" && Type(obj) != "Array"
        return '"' . obj . '"'
    isArr := (Type(obj) == "Array")
    str := isArr ? "[" : "{"
    for k, v in obj {
        key := isArr ? "" : '"' . k . '":'
        if (Type(v) == "Map" || Type(v) == "Array")
            str .= key . MapToJson(v) . ","
        else if IsNumber(v)
            str .= key . v . ","
        else {
            escaped := StrReplace(v, "\", "\\")
            escaped := StrReplace(escaped, '"', '\"')
            str .= key . '"' . escaped . '",'
        }
    }
    return RTrim(str, ",") . (isArr ? "]" : "}")
}