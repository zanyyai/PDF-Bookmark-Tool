import sys
import json
import os
import fitz  # PyMuPDF

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"status": "error", "message": "未传入参数文件路径"}))
        sys.exit(1)

    json_file_path = sys.argv[1]
    
    try:
        # 修改点：encoding 改为 utf-8-sig，自动忽略 BOM 头
        with open(json_file_path, "r", encoding="utf-8-sig") as f:
            params = json.load(f)
        
        pdf_path = params["pdf"]
        toc_data = params["toc"]
        output_path = params["output"]
        
        toc = [[int(item["level"]), item["title"], int(item["page"])] for item in toc_data]
        
        doc = fitz.open(pdf_path)
        doc.set_toc(toc)
        doc.save(output_path)
        doc.close()
        
        print(json.dumps({"status": "success"}))
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))