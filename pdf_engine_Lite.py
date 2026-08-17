import sys
import json
import base64
import fitz  # PyMuPDF

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)

    raw_input = sys.argv[1]
    
    try:
        try:
            decoded_json = base64.b64decode(raw_input).decode('utf-8')
        except Exception:
            decoded_json = raw_input

        params = json.loads(decoded_json)
        
        pdf_path = params["pdf"]
        toc_data = params["toc"]
        output_path = params["output"]
        
        # PyMuPDF 要求的格式: [level, title, page]
        toc = [[int(item["level"]), item["title"], int(item["page"])] for item in toc_data]
        
        doc = fitz.open(pdf_path)
        doc.set_toc(toc)  # 覆盖写入新书签目录
        doc.save(output_path)
        doc.close()
        
        print(json.dumps({"status": "success"}))
    except Exception as e:
        print(json.dumps({"status": "error", "message": str(e)}))