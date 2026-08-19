#Requires AutoHotkey v2.0
#SingleInstance Force

ConfigFile := A_ScriptDir . "\rules_config.json"
Global ConfigData := Map()
Global CurrentCandidates := [] ; 存储查找过程中扫描到的候选行文本

MainGui := Gui("+Resize", "PDF 目录提取工具 (带页码范围与规则配置)")

; 1. 文件选择
MainGui.Add("Text", "x10 y15 w70 h20", "PDF 文件:")
EditPdfPath := MainGui.Add("Edit", "x80 y12 w400 h20", "")
BtnBrowse := MainGui.Add("Button", "x490 y10 w70 h24", "浏览...")

; 2. 预设规则配置组
MainGui.Add("GroupBox", "x10 y40 w550 h50", "预设配置方案")
MainGui.Add("Text", "x20 y62 w60 h20", "选择方案:")
DDLConfigs := MainGui.Add("DropDownList", "x80 y58 w180 Choose1", ["通用教材/图书"])
BtnLoadConfig := MainGui.Add("Button", "x270 y57 w80 h24", "加载方案")
EditConfigName := MainGui.Add("Edit", "x360 y58 w110 h20", "新配置名")
BtnSaveConfig := MainGui.Add("Button", "x480 y57 w70 h24", "保存方案")

; 3. 提取规则组
MainGui.Add("GroupBox", "x10 y100 w550 h150", "提取规则与范围限制")

MainGui.Add("Text", "x20 y120 w70 h20", "匹配页码范围:")
MainGui.Add("Text", "x90 y120 w20 h20", "从")
EditStartPage := MainGui.Add("Edit", "x110 y117 w40 h20", "1")
MainGui.Add("Text", "x155 y120 w20 h20", "页")
MainGui.Add("Text", "x180 y120 w20 h20", "到")
EditEndPage := MainGui.Add("Edit", "x200 y117 w40 h20", "20")
MainGui.Add("Text", "x245 y120 w120 h20", "页 (0或不填设为末页)")

MainGui.Add("Text", "x380 y120 w60 h20", "提取模式:")
RadioSmart := MainGui.Add("Radio", "x440 y120 w50 h20 Checked", "智能")
RadioRegex := MainGui.Add("Radio", "x490 y120 w50 h20", "正则")

MainGui.Add("Text", "x20 y150 w100 h20", "目录起始头(正则):")
EditHeaderPattern := MainGui.Add("Edit", "x120 y147 w220 h20", ".*目\s*录.*")
MainGui.Add("Text", "x350 y150 w80 h20", "中断容错行数:")
EditMaxGap := MainGui.Add("Edit", "x430 y147 w40 h20", "3")

MainGui.Add("Text", "x20 y180 w100 h20", "全局正则(备用):")
EditExtractPattern := MainGui.Add("Edit", "x120 y177 w320 h20", "^第[一二三四五六七八九十0-9]+章.*")

BtnSearch := MainGui.Add("Button", "x450 y175 w100 h26", "查找")

; 4. 分级规则组
MainGui.Add("GroupBox", "x10 y255 w550 h55", "目录分级设置")
MainGui.Add("Text", "x20 y275 w90 h20", "分级匹配正则:")
EditLevelPattern := MainGui.Add("Edit", "x110 y272 w230 h20", "^\d+\.\d+")
MainGui.Add("Text", "x350 y275 w40 h20", "层级:")
DDLLevel := MainGui.Add("DropDownList", "x390 y272 w50 Choose2", ["1", "2", "3", "4"])
BtnApplyLevel := MainGui.Add("Button", "x450 y270 w100 h24", "应用分级")

BtnFindPages := MainGui.Add("Button", "x450 y315 w100 h24", "校对正文页码")

; 5. ListView 查找结果与新增【添加】按钮
MainGui.Add("Text", "x10 y345 w100 h18", "查找结果:")
BtnAddCandidate := MainGui.Add("Button", "x430 y340 w120 h22", "添加扫描内容") ; 新增添加按钮

LV := MainGui.Add("ListView", "x10 y365 w550 h120 Grid AltSubmit", ["序号", "层级", "目录标题", "页码"])
LV.ModifyCol(1, 50)
LV.ModifyCol(2, 50)
LV.ModifyCol(3, 330)
LV.ModifyCol(4, 80)

; 6. 查找日志输出框
MainGui.Add("Text", "x10 y490 w100 h18", "查找日志:")
EditLog := MainGui.Add("Edit", "x10 y510 w550 h100 ReadOnly VScroll", "")

; 7. 底部操作按钮
BtnInsert := MainGui.Add("Button", "x10 y620 w120 h30", "插入目录到PDF")
BtnDelete := MainGui.Add("Button", "x140 y620 w120 h30", "删除PDF原目录")

; 事件绑定
BtnBrowse.OnEvent("Click", (*) => BrowsePDF())
BtnSearch.OnEvent("Click", (*) => SearchTOC())
BtnAddCandidate.OnEvent("Click", (*) => AddCandidatesToLV()) ; 绑定添加功能
BtnApplyLevel.OnEvent("Click", (*) => ApplyLevel())
BtnFindPages.OnEvent("Click", (*) => FindPages())
BtnInsert.OnEvent("Click", (*) => InsertTOC())
BtnDelete.OnEvent("Click", (*) => DeleteTOC())
BtnLoadConfig.OnEvent("Click", (*) => LoadSelectedConfig())
BtnSaveConfig.OnEvent("Click", (*) => SaveCurrentConfig())
MainGui.OnEvent("Close", (*) => ExitApp())

; 初始化配置文件
InitConfigFile()

MainGui.Show("w570 h660")

; --- 逻辑函数 ---

InitConfigFile() {
    Global ConfigData, ConfigFile, DDLConfigs
    if FileExist(ConfigFile) {
        try {
            content := FileRead(ConfigFile, "UTF-8")
            ConfigData := SimpleJsonParse(content)
        }
    }
    
    if (ConfigData.Count == 0) {
        ConfigData["通用教材/图书"] := Map(
            "mode", "smart",
            "header_pattern", ".*目\s*录.*",
            "extract_pattern", "^第[一二三四五六七八九十0-9]+章.*",
            "level_pattern", "^\d+\.\d+",
            "max_gap", "3",
            "start_page", "1",
            "end_page", "20"
        )
        SaveConfigToFile()
    }
    
    UpdateConfigDDL()
}

UpdateConfigDDL() {
    Global ConfigData, DDLConfigs
    items := []
    for k, v in ConfigData {
        items.Push(k)
    }
    DDLConfigs.Delete()
    DDLConfigs.Add(items)
    if (items.Length > 0)
        DDLConfigs.Choose(1)
}

LoadSelectedConfig() {
    Global ConfigData, DDLConfigs
    cfgName := DDLConfigs.Text
    if (cfgName != "" && ConfigData.Has(cfgName)) {
        cfg := ConfigData[cfgName]
        EditHeaderPattern.Value := cfg.Has("header_pattern") ? cfg["header_pattern"] : ".*目\s*录.*"
        EditExtractPattern.Value := cfg.Has("extract_pattern") ? cfg["extract_pattern"] : ""
        EditLevelPattern.Value := cfg.Has("level_pattern") ? cfg["level_pattern"] : ""
        EditMaxGap.Value := cfg.Has("max_gap") ? cfg["max_gap"] : "3"
        EditStartPage.Value := cfg.Has("start_page") ? cfg["start_page"] : "1"
        EditEndPage.Value := cfg.Has("end_page") ? cfg["end_page"] : "20"
        
        if (cfg.Has("mode") && cfg["mode"] == "regex")
            RadioRegex.Value := 1
        else
            RadioSmart.Value := 1
            
        MsgBox("规则配置 [" . cfgName . "] 加载成功！", "提示", 64)
    }
}

SaveCurrentConfig() {
    Global ConfigData, EditConfigName
    cfgName := EditConfigName.Value
    if (cfgName == "") {
        MsgBox("请输入规则配置名称！", "警告", 48)
        return
    }
    
    ConfigData[cfgName] := Map(
        "mode", RadioSmart.Value ? "smart" : "regex",
        "header_pattern", EditHeaderPattern.Value,
        "extract_pattern", EditExtractPattern.Value,
        "level_pattern", EditLevelPattern.Value,
        "max_gap", EditMaxGap.Value,
        "start_page", EditStartPage.Value,
        "end_page", EditEndPage.Value
    )
    
    SaveConfigToFile()
    UpdateConfigDDL()
    DDLConfigs.Text := cfgName
    MsgBox("方案 [" . cfgName . "] 已保存至配置文件！", "成功", 64)
}

SaveConfigToFile() {
    Global ConfigData, ConfigFile
    jsonStr := MapToJson(ConfigData)
    if FileExist(ConfigFile)
        FileDelete(ConfigFile)
    FileAppend(jsonStr, ConfigFile, "UTF-8")
}

BrowsePDF() {
    SelectedFile := FileSelect(3, , "选择 PDF 文件", "PDF 文件 (*.pdf)")
    if (SelectedFile != "")
        EditPdfPath.Value := SelectedFile
}

SearchTOC() {
    Global CurrentCandidates
    PdfPath := EditPdfPath.Value
    if (!FileExist(PdfPath)) {
        MsgBox("请先选择有效的 PDF 文件！", "警告", 48)
        return
    }
    
    mode := RadioSmart.Value ? "smart" : "regex"
    params := Map(
        "pdf", PdfPath,
        "mode", mode,
        "start_page", EditStartPage.Value == "" ? "1" : EditStartPage.Value,
        "end_page", EditEndPage.Value == "" ? "0" : EditEndPage.Value,
        "header_pattern", EditHeaderPattern.Value,
        "max_gap", EditMaxGap.Value,
        "pattern", EditExtractPattern.Value
    )
    
    jsonStr := MapToJson(params)
    resultText := RunPython("extract", jsonStr)
    
    LV.Delete()
    EditLog.Value := ""
    CurrentCandidates := []
    
    ; 打印日志
    logsText := ParseLogsFromJson(resultText)
    EditLog.Value := logsText
    
    if InStr(resultText, '"error"') {
        return
    }
    
    ; 提取自动匹配到的目录结果
    Pos := 1
    Pattern1 := '\{"title":\s*"(.*?)",\s*"page":\s*(\d+)\}'
    Pattern2 := '\{"page":\s*(\d+),\s*"title":\s*"(.*?)"\}'
    
    ; 解析 Python 返回的 candidates 候选数据
    CurrentCandidates := ParseCandidatesFromJson(resultText)
    
    ; 填充匹配成功的列表
    Index := 1
    While RegExMatch(resultText, Pattern1, &m, Pos) || RegExMatch(resultText, Pattern2, &m, Pos) {
        if (m[1] != "" && m[2] != "") {
            title := UnescapeJson(m[1])
            page := m[2]
        } else {
            title := UnescapeJson(m[4])
            page := m[3]
        }
        LV.Add("", Index, 1, title, page)
        Index++
        Pos := m.Pos + m.Len
    }
}

; 添加扫描到的候选内容到表格，或者手动添加单行
AddCandidatesToLV() {
    Global CurrentCandidates, LV
    
    if (CurrentCandidates.Length > 0) {
        addedCount := 0
        startIndex := LV.GetCount() + 1
        
        for item in CurrentCandidates {
            LV.Add("", startIndex, 1, item["title"], item["page"])
            startIndex++
            addedCount++
        }
        
        MsgBox("成功将日志中扫描到的 " . addedCount . " 条候选文本添加到列表中！", "添加成功", 64)
        CurrentCandidates := [] ; 添加完成后清空，避免重复添加
    } else {
        ; 若无候选内容，提供手动新增单行功能
        IB := InputBox("请输入要手动添加的目录标题与页码 (格式: 标题,页码):", "手动添加目录", "w350 h130", "第一章 概述,1")
        if (IB.Result == "OK" && IB.Value != "") {
            parts := StrSplit(IB.Value, ",")
            title := parts[1]
            page := (parts.Length > 1) ? Integer(parts[2]) : 1
            idx := LV.GetCount() + 1
            LV.Add("", idx, 1, title, page)
        }
    }
}

ApplyLevel() {
    LevelPattern := EditLevelPattern.Value
    if (LevelPattern == "")
        return
        
    SelectedLevel := DDLLevel.Text
    Loop LV.GetCount() {
        title := LV.GetText(A_Index, 3)
        if RegExMatch(title, LevelPattern) {
            LV.Modify(A_Index, "Col2", SelectedLevel)
        }
    }
}

FindPages() {
    PdfPath := EditPdfPath.Value
    if (LV.GetCount() == 0)
        return
        
    items := []
    Loop LV.GetCount() {
        title := LV.GetText(A_Index, 3)
        page := Integer(LV.GetText(A_Index, 4))
        items.Push(Map("title", title, "page", page))
    }
    
    params := Map("pdf", PdfPath, "items", items)
    jsonStr := MapToJson(params)
    
    resultText := RunPython("find_pages", jsonStr)
    
    LV.Delete()
    Pos := 1
    Index := 1
    Pattern := '\{"page":\s*(-?\d+),\s*"title":\s*"(.*?)"\}'
    While RegExMatch(resultText, Pattern, &m, Pos) {
        title := UnescapeJson(m[2])
        page := m[1]
        LV.Add("", Index, 1, title, page)
        Index++
        Pos := m.Pos + m.Len
    }
}

InsertTOC() {
    PdfPath := EditPdfPath.Value
    if (LV.GetCount() == 0) {
        MsgBox("列表为空，无法插入目录！", "提示", 48)
        return
    }
    
    SplitPath(PdfPath, &fname, &fdir, &fext, &fname_no_ext)
    outputPath := fdir "\" fname_no_ext "_带目录.pdf"
    
    toc := []
    Loop LV.GetCount() {
        lvl := Integer(LV.GetText(A_Index, 2))
        title := LV.GetText(A_Index, 3)
        page := Integer(LV.GetText(A_Index, 4))
        toc.Push(Map("level", lvl, "title", title, "page", page))
    }
    
    params := Map("pdf", PdfPath, "toc", toc, "output", outputPath)
    jsonStr := MapToJson(params)
    
    res := RunPython("insert", jsonStr)
    if InStr(res, "success") {
        MsgBox("目录已成功插入！新文件保存在：`n" . outputPath, "成功", 64)
        Run(outputPath)
    } else {
        MsgBox("写入失败：" . res, "错误", 16)
    }
}

DeleteTOC() {
    PdfPath := EditPdfPath.Value
    if (MsgBox("是否确定要清空该 PDF 的所有目录结构？", "确认操作", 308) == "No")
        return
        
    SplitPath(PdfPath, &fname, &fdir, &fext, &fname_no_ext)
    outputPath := fdir "\" fname_no_ext "_无目录.pdf"
    
    params := Map("pdf", PdfPath, "output", outputPath)
    jsonStr := MapToJson(params)
    
    res := RunPython("clear", jsonStr)
    if InStr(res, "success") {
        MsgBox("已生成删除目录后的 PDF：`n" . outputPath, "成功", 64)
    }
}

; --- 辅助函数 ---

RunPython(action, jsonParam) {
    buf := Buffer(StrPut(jsonParam, "UTF-8"))
    StrPut(jsonParam, buf, "UTF-8")
    b64Str := ExecBase64Encode(buf)
    
    cmd := 'python "' . A_ScriptDir . '\pdf_engine.py" ' . action . ' "' . b64Str . '"'
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(cmd)
    return exec.StdOut.ReadAll()
}

ExecBase64Encode(buf) {
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size - 1, "UInt", 0x40000001, "Ptr", 0, "UInt*", &Size := 0)
    outBuf := Buffer(Size * 2)
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size - 1, "UInt", 0x40000001, "Ptr", outBuf, "UInt*", &Size)
    return StrGet(outBuf)
}

MapToJson(obj) {
    if Type(obj) != "Map" && Type(obj) != "Array"
        return '"' . obj . '"'
    
    isArr := (Type(obj) == "Array")
    str := isArr ? "[" : "{"
    
    for k, v in obj {
        key := isArr ? "" : '"' . k . '":'
        if (Type(v) == "Map" || Type(v) == "Array") {
            str .= key . MapToJson(v) . ","
        } else if IsNumber(v) {
            str .= key . v . ","
        } else {
            escaped := StrReplace(v, "\", "\\")
            escaped := StrReplace(escaped, '"', '\"')
            str .= key . '"' . escaped . '",'
        }
    }
    str := RTrim(str, ",")
    str .= isArr ? "]" : "}"
    return str
}

SimpleJsonParse(jsonStr) {
    res := Map()
    Pos := 1
    BlockPattern := '"([^"]+)":\s*\{([^}]+)\}'
    While RegExMatch(jsonStr, BlockPattern, &m, Pos) {
        cfgName := m[1]
        subBody := m[2]
        
        subMap := Map()
        subPos := 1
        KVPattern := '"([^"]+)":\s*"([^"]*)"'
        While RegExMatch(subBody, KVPattern, &subM, subPos) {
            subMap[subM[1]] := subM[2]
            subPos := subM.Pos + subM.Len
        }
        res[cfgName] := subMap
        Pos := m.Pos + m.Len
    }
    return res
}

ParseLogsFromJson(jsonStr) {
    logText := ""
    if RegExMatch(jsonStr, 's)"logs":\s*\[(.*?)\]', &mLog) {
        logBlock := mLog[1]
        pos := 1
        while RegExMatch(logBlock, '"(.*?)"', &mL, pos) {
            logText .= UnescapeJson(mL[1]) . "`r`n"
            pos := mL.Pos + mL.Len
        }
    }
    if (logText == "") {
        logText := jsonStr
    }
    return logText
}

ParseCandidatesFromJson(jsonStr) {
    cands := []
    if RegExMatch(jsonStr, 's)"candidates":\s*\[(.*?)\]', &mCand) {
        candBlock := mCand[1]
        pos := 1
        Pattern1 := '\{"title":\s*"(.*?)",\s*"page":\s*(\d+)\}'
        Pattern2 := '\{"page":\s*(\d+),\s*"title":\s*"(.*?)"\}'
        while RegExMatch(candBlock, Pattern1, &m, pos) || RegExMatch(candBlock, Pattern2, &m, pos) {
            if (m[1] != "" && m[2] != "") {
                t := UnescapeJson(m[1])
                p := m[2]
            } else {
                t := UnescapeJson(m[4])
                p := m[3]
            }
            cands.Push(Map("title", t, "page", p))
            pos := m.Pos + m.Len
        }
    }
    return cands
}

UnescapeJson(str) {
    str := StrReplace(str, '\"', '"')
    str := StrReplace(str, '\\', '\')
    str := StrReplace(str, '\n', '`n')
    str := StrReplace(str, '\r', '')
    return str
}