import sys
import json
import re
import base64
import fitz  # PyMuPDF

def get_layout_sorted_lines(page, y_tolerance=5):
    """
    核心算法：通过 X/Y 坐标将被 Block 拆散的标题和页码强制按物理行重新组合
    """
    # 获取页面上所有词及其坐标 (x0, y0, x1, y1, word, block_no, line_no, word_no)
    words = page.get_text("words")
    if not words:
        return []

    # 1. 先按垂直 Y 坐标排序
    words.sort(key=lambda w: (w[1], w[0]))

    lines = []
    current_line_words = [words[0]]

    # 2. 遍历词，Y 坐标差距小于 y_tolerance 的归为同一物理行
    for w in words[1:]:
        # 与当前行第一个词的 y0 比较
        if abs(w[1] - current_line_words[0][1]) <= y_tolerance:
            current_line_words.append(w)
        else:
            # 同一行内的词按 X 坐标从左到右排序并拼接
            current_line_words.sort(key=lambda item: item[0])
            line_str = "".join([item[4] for item in current_line_words])
            lines.append(line_str)
            current_line_words = [w]

    if current_line_words:
        current_line_words.sort(key=lambda item: item[0])
        lines.append("".join([item[4] for item in current_line_words]))

    return lines

def extract_smart_toc(pdf_path, header_pattern, start_page=1, end_page=0, max_gap=5):
    """根据物理坐标按行重构文本后提取目录"""
    logs = []
    results = []
    candidates = []
    
    try:
        doc = fitz.open(pdf_path)
    except Exception as e:
        logs.append(f"[错误] 打开 PDF 文件失败: {str(e)}")
        return {"status": "error", "results": [], "candidates": [], "logs": logs}
    
    total_pages = len(doc)
    start_idx = max(0, start_page - 1)
    end_idx = total_pages if end_page <= 0 else min(total_pages, end_page)
    
    logs.append(f"[信息] 开启物理坐标重构逻辑查找目录...")
    logs.append(f"[配置] PDF总页数: {total_pages} | 检索页码: 第 {start_idx + 1} 页 至 第 {end_idx} 页")
    
    try:
        header_re = re.compile(header_pattern, re.IGNORECASE)
    except Exception as e:
        logs.append(f"[错误] 起始头正则表达式错误: {str(e)}")
        return {"status": "error", "results": [], "candidates": [], "logs": logs}
        
    # 匹配末尾数字（容忍空格或点号）
    num_end_re = re.compile(r'[\.·…\s]+(\d+)\s*$|(?<=\s)(\d+)\s*$|(\d+)\s*$')
    
    state = "SEARCH_HEADER"
    gap_count = 0
    buffer_lines = []
    
    for page_num in range(start_idx, end_idx):
        page = doc[page_num]
        
        # 🔑 关键步骤：改用物理坐标重构按行提取
        lines = get_layout_sorted_lines(page, y_tolerance=5)
        
        for line_str in lines:
            # 清理特殊空格
            line_str = line_str.replace('\xa0', ' ').replace('\u3000', ' ').strip()
            if not line_str:
                continue
            
            if state == "SEARCH_HEADER":
                if header_re.search(line_str):
                    state = "IN_TOC"
                    gap_count = 0
                    buffer_lines = []
                    logs.append(f"[匹配] 第 {page_num + 1} 页找到目录头: \"{line_str}\"")
            
            elif state == "IN_TOC":
                # 过滤掉纯解释性文本或说明
                if "★加★的文件" in line_str or "重点法律依据" in line_str:
                    continue

                match = num_end_re.search(line_str)
                
                if match:
                    # 提取末尾数字
                    target_page = int(match.group(1) or match.group(2) or match.group(3))
                    full_line = " ".join(buffer_lines + [line_str]) if buffer_lines else line_str
                    clean_title = num_end_re.sub('', full_line).strip()
                    
                    if clean_title:
                        results.append({"title": clean_title, "page": target_page})
                        logs.append(f"[提取] 第 {page_num + 1} 页匹配成功: \"{clean_title}\" -> 页码 {target_page}")
                    
                    buffer_lines = []
                    gap_count = 0
                else:
                    logs.append(f"[扫描/未匹配页码] 第 {page_num + 1} 页: \"{line_str}\"")
                    candidates.append({"title": line_str, "page": page_num + 1})
                    
                    current_max_gap = max_gap if len(results) > 0 else max(max_gap, 15)
                    gap_count += 1
                    buffer_lines.append(line_str)
                    
                    if gap_count > current_max_gap:
                        logs.append(f"[中断] 连续 {gap_count} 行未找到带页码条目，终止查找")
                        return {"status": "success", "results": results, "candidates": candidates, "logs": logs}
                        
    logs.append(f"[总结] 查找结束，共提取到 {len(results)} 条格式完整目录")
    return {"status": "success", "results": results, "candidates": candidates, "logs": logs}

def extract_text_global(pdf_path, regex_pattern, start_page=1, end_page=0):
    """全局正则匹配模式"""
    logs = []
    results = []
    try:
        doc = fitz.open(pdf_path)
    except Exception as e:
        logs.append(f"[错误] 打开 PDF 失败: {str(e)}")
        return {"status": "error", "results": [], "candidates": [], "logs": logs}
        
    total_pages = len(doc)
    start_idx = max(0, start_page - 1)
    end_idx = total_pages if end_page <= 0 else min(total_pages, end_page)
    pattern = re.compile(regex_pattern, re.IGNORECASE)
    
    for page_num in range(start_idx, end_idx):
        page = doc[page_num]
        lines = get_layout_sorted_lines(page, y_tolerance=5)
        for line_str in lines:
            line_str = line_str.replace('\xa0', ' ').replace('\u3000', ' ').strip()
            if line_str and pattern.search(line_str):
                clean_title = re.sub(r'[\.·…\s]+\d*$', '', line_str).strip()
                if clean_title:
                    results.append({"title": clean_title, "page": page_num + 1})
                    logs.append(f"[提取] 第 {page_num + 1} 页匹配条目: \"{clean_title}\"")
                    
    return {"status": "success", "results": results, "candidates": [], "logs": logs}

def find_pages(pdf_path, items):
    doc = fitz.open(pdf_path)
    for item in items:
        title = item["title"]
        clean_title = re.sub(r'[\.\s\d]+$', '', title).strip()
        matched_page = -1
        if clean_title:
            for page_num in range(len(doc)):
                text = doc[page_num].get_text("text")
                if clean_title in text:
                    matched_page = page_num + 1
                    break
        item["page"] = matched_page if matched_page != -1 else item.get("page", 1)
    return items

def insert_toc(pdf_path, toc_data, output_path):
    doc = fitz.open(pdf_path)
    toc = [[item["level"], item["title"], item["page"]] for item in toc_data]
    doc.set_toc(toc)
    doc.save(output_path)
    doc.close()

def clear_toc(pdf_path, output_path):
    doc = fitz.open(pdf_path)
    doc.set_toc([])
    doc.save(output_path)
    doc.close()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(1)

    action = sys.argv[1]
    raw_input = sys.argv[2]
    
    try:
        try:
            decoded_json = base64.b64decode(raw_input).decode('utf-8')
        except Exception:
            decoded_json = raw_input

        params = json.loads(decoded_json)
        
        if action == "extract":
            mode = params.get("mode", "smart")
            start_p = int(params.get("start_page", 1))
            end_p = int(params.get("end_page", 0))
            
            if mode == "smart":
                res = extract_smart_toc(
                    params["pdf"], 
                    params.get("header_pattern", ".*目\s*录.*"),
                    start_page=start_p,
                    end_page=end_p,
                    max_gap=int(params.get("max_gap", 3))
                )
            else:
                res = extract_text_global(
                    params["pdf"], 
                    params.get("pattern", ""), 
                    start_page=start_p, 
                    end_page=end_p
                )
                
            print(json.dumps(res, ensure_ascii=False))
            
        elif action == "find_pages":
            res = find_pages(params["pdf"], params["items"])
            print(json.dumps(res, ensure_ascii=False))
        elif action == "insert":
            insert_toc(params["pdf"], params["toc"], params["output"])
            print(json.dumps({"status": "success"}))
        elif action == "clear":
            clear_toc(params["pdf"], params["output"])
            print(json.dumps({"status": "success"}))
    except Exception as e:
        print(json.dumps({"status": "error", "logs": [f"[错误] 系统异常: {str(e)}"]}, ensure_ascii=False))