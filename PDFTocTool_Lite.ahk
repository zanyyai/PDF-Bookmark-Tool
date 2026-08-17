#Requires AutoHotkey v2.0
#SingleInstance Force

MainGui := Gui("+Resize", "PDF 智能书签写入工具 (偏移量实时同步版)")

; 1. 文件选择
MainGui.Add("Text", "x10 y15 w70 h20", "PDF 文件:")
EditPdfPath := MainGui.Add("Edit", "x80 y12 w380 h20", "")
BtnBrowse := MainGui.Add("Button", "x470 y10 w80 h24", "浏览...")

; 2. 页码偏移量 (绑定 Change 事件，修改即实时刷新列表)
MainGui.Add("Text", "x10 y45 w80 h20", "页码偏移:")
EditOffset := MainGui.Add("Edit", "x80 y42 w60 h20", "0")
MainGui.Add("Text", "x150 y45 w390 h20", "(PDF实际页码 = 目录印刷页码 + 偏移量，支持负数)")

; 3. 多级正则匹配规则配置区
MainGui.Add("GroupBox", "x10 y70 w540 h150", "多级书签匹配规则配置 (留空表示不启用该级)")

MainGui.Add("Text", "x20 y92 w70 h20", "一级书签:")
EditRegexL1 := MainGui.Add("Edit", "x90 y89 w170 h20", "^[一二三四五六七八九十]+[、\.]")

MainGui.Add("Text", "x270 y92 w70 h20", "二级书签:")
EditRegexL2 := MainGui.Add("Edit", "x340 y89 w200 h20", "^【.*】")

MainGui.Add("Text", "x20 y122 w70 h20", "三级书签:")
EditRegexL3 := MainGui.Add("Edit", "x90 y119 w170 h20", "^\d+\.\s*")

MainGui.Add("Text", "x270 y122 w70 h20", "行匹配:")
EditRegexLine := MainGui.Add("Edit", "x340 y119 w200 h20", "\d+\s*页?\s*$")

MainGui.Add("Text", "x20 y152 w70 h20", "底级书签:")
EditRegexTitle := MainGui.Add("Edit", "x90 y149 w170 h20", "^(.*?)(?=\s*[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$)")

MainGui.Add("Text", "x270 y152 w70 h20", "页码提取:")
EditRegexPage := MainGui.Add("Edit", "x340 y149 w200 h20", "(\d+)\s*页?\s*$")

MainGui.Add("Text", "x20 y185 w520 h20", "💡 说明：修改上方偏移量时，列表中的目标页码会自动实时重新计算。")

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

; 事件绑定
BtnBrowse.OnEvent("Click", (*) => BrowsePDF())
BtnParse.OnEvent("Click", (*) => ParseTextToLV())
BtnInsert.OnEvent("Click", (*) => WriteToPDF())

; 核心变更：偏移量修改时，如果粘贴区有内容，自动实时更新列表
EditOffset.OnEvent("Change", (*) => AutoRefreshLV())

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

; 安全获取数值型的偏移量
GetOffsetValue() {
    rawStr := Trim(EditOffset.Value)
    if (rawStr == "" || rawStr == "-")
        return 0
    if RegExMatch(rawStr, "^-?\d+$")
        return Integer(rawStr)
    return 0
}

ParseTextToLV() {
    rawText := EditInputText.Value
    if (Trim(rawText) == "") {
        MsgBox("请先粘贴文本！", "提示", 48)
        return
    }

    regL1 := EditRegexL1.Value
    regL2 := EditRegexL2.Value
    regL3 := EditRegexL3.Value
    regLine := EditRegexLine.Value
    regTitle := EditRegexTitle.Value
    regPage := EditRegexPage.Value
    
    ; 使用安全计算偏移量逻辑
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
        }

        ; 1. 一级高级书签
        if (regL1 != "" && RegExMatch(lineStr, regL1)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL1 := Trim(cleanTitle)
            activeL2 := ""
            activeL3 := ""
            
            item := Map("type", "HEADER", "title", activeL1, "page", linePage, "level", 1)
            parsedItems.Push(item)
            continue
        }

        ; 2. 二级高级书签
        if (regL2 != "" && RegExMatch(lineStr, regL2)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL2 := Trim(cleanTitle)
            activeL3 := ""
            
            lvl := (activeL1 != "" ? 1 : 0) + 1
            item := Map("type", "HEADER", "title", activeL2, "page", linePage, "level", lvl)
            parsedItems.Push(item)
            continue
        }

        ; 3. 三级高级书签
        if (regL3 != "" && RegExMatch(lineStr, regL3)) {
            cleanTitle := RegExReplace(lineStr, "[\.·…\s\-—–|_]*[pP|第]?\s*\d+\s*页?$", "")
            activeL3 := Trim(cleanTitle)
            
            lvl := (activeL1 != "" ? 1 : 0) + (activeL2 != "" ? 1 : 0) + 1
            item := Map("type", "HEADER", "title", activeL3, "page", linePage, "level", lvl)
            parsedItems.Push(item)
            continue
        }

        ; 4. 底级书签
        isMatchLine := (regLine == "" || RegExMatch(lineStr, regLine))
        if (isMatchLine && linePage > 0) {
            titleStr := lineStr
            if (regTitle != "" && RegExMatch(lineStr, regTitle, &mTitle)) {
                titleStr := Trim(mTitle[1] != "" ? mTitle[1] : mTitle[0])
            }
            cleanTitle := RegExReplace(titleStr, "^[\s\t*★]+", "")

            parentCount := (activeL1 != "" ? 1 : 0) + (activeL2 != "" ? 1 : 0) + (activeL3 != "" ? 1 : 0)
            leafLvl := parentCount + 1

            item := Map("type", "LEAF", "title", cleanTitle, "page", linePage, "level", leafLvl)
            parsedItems.Push(item)
        }
    }

    ; 后处理：补全无页码的高级书签
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

    ; 输出渲染到 ListView
    Index := 1
    for item in parsedItems {
        finalPage := item["page"] + offset
        ; 保证最终页码至少为 1，防止出现 0 或负数页码
        if (finalPage < 1) {
            finalPage := 1
        }
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
    
    ; 写入前强制按最新偏移量重新计算一次，确保绝对同步
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

    buf := Buffer(StrPut(jsonStr, "UTF-8"))
    StrPut(jsonStr, buf, "UTF-8")
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size - 1, "UInt", 0x40000001, "Ptr", 0, "UInt*", &Size := 0)
    outBuf := Buffer(Size * 2)
    DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size - 1, "UInt", 0x40000001, "Ptr", outBuf, "UInt*", &Size)
    b64Str := StrGet(outBuf)

    cmd := 'python "' . A_ScriptDir . '\pdf_engine_Lite.py" "' . b64Str . '"'
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(cmd)
    res := exec.StdOut.ReadAll()

    if InStr(res, "success") {
        MsgBox("书签写入成功！文件保存在：`n" . outputPath, "成功", 64)
        Run(outputPath)
    } else {
        MsgBox("写入失败：" . res, "错误", 16)
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