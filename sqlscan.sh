#!/bin/bash

# ===============================================
# Ultimate Web Vulnerability Scanner (Safe Test)
# ===============================================

# دالة لعرض الفواصل
separator() {
    echo -e "\e[1;33m====================================================================\e[0m"
}

# ===========================================
# دالة التحقق والتثبيت التلقائي للأدوات
# ===========================================
ensure_tools() {
    local tool=$1
    if ! command -v "$tool" &> /dev/null; then
        echo -e "\e[1;33m[!] Tool '$tool' not found. Installing automatically...\e[0m"
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install "$tool" -y
        
        if [ $? -eq 0 ]; then
            echo -e "\e[1;32m[+] Tool '$tool' installed successfully.\e[0m"
        else
            echo -e "\e[1;31m[-] Failed to install '$tool'. Please install it manually.\e[0m"
        fi
    else
        echo -e "\e[1;32m[+] Tool '$tool' is ready.\e[0m"
    fi
}

echo -e "\e[1;32m[+] Ultimate Web Vulnerability Automation Script (Safe Test)\e[0m"
separator

# 1. التحقق من الأدوات وتثبيتها
echo -e "\e[1;36m[*] Checking dependencies...\e[0m"
ensure_tools "sqlmap"
ensure_tools "xsser"
separator

# إعداد المعلومات الأساسية
while true; do
    echo -e "\e[1;32m[+] Enter target URL:\e[0m"
    read target
    
    if [[ "$target" =~ ^https?:// ]]; then
        break
    else
        echo -e "\e[1;31m[!] Invalid URL. Use http:// or https://\e[0m"
    fi
done

# إعداد المجلدات
mkdir -p ./sqlmap_logs
site_safe_name=$(echo "$target" | sed 's/https\?:\/\///g' | tr '/' '_')

# تعريف مسارات الملفات
sql_errors="./sqlmap_logs/${site_safe_name}.Errors"
sql_data="./sqlmap_logs/${site_safe_name}.data"
xss_log="./sqlmap_logs/${site_safe_name}.XSS_Logs.txt"
xss_payloads="./sqlmap_logs/${site_safe_name}.Successful_Payloads.txt"

separator
echo -e "\e[1;36m[*] Target: $target\e[0m"
echo -e "\e[1;36m[*] Files will be saved in: ./sqlmap_logs/\e[0m"

# ===========================================
# 1. SQL Injection Function
# ===========================================
run_sql_scan() {
    separator
    echo -e "\e[1;31m[*] Starting SQL Injection Scan (SQLMap)...\e[0m"
    
    if [[ "$target" == *"?"* ]]; then
        base_cmd="sqlmap -u \"$target\" --batch --random-agent --banner"
    else
        base_cmd="sqlmap -u \"$target\" --batch --random-agent --forms --crawl=2 --banner"
    fi

    scan_output=$(eval $base_cmd 2>&1)
    vuln_report=$(echo "$scan_output" | grep -i "Parameter:" -A 15 | grep -E "Parameter:|Type:|Title:|Payload:")
    
    if [ -n "$vuln_report" ]; then
        { echo "VULNERABILITY REPORT (SQLi):"; echo "$vuln_report"; } > "$sql_errors"
        echo -e "\e[1;32m[+] SQLi Found! Check $sql_errors\e[0m"
        echo "$vuln_report"
    else
        echo "No SQLi found." > "$sql_errors"
    fi

    # --- Session Locking Logic ---
    extracted_post_url=$(echo "$scan_output" | grep "^POST http" | head -n 1 | cut -d' ' -f2)
    extracted_post_data=$(echo "$scan_output" | grep "^POST data:" | head -n 1 | cut -d' ' -f3-)

    if [[ -n "$extracted_post_url" && -n "$extracted_post_data" ]]; then
        exploit_cmd="sqlmap -u \"$extracted_post_url\" --data=\"$extracted_post_data\" --batch --random-agent"
    else
        exploit_cmd="sqlmap -u \"$target\" --batch --random-agent"
    fi
    # ----------------------------

    read -p "Do you want to enumerate Databases for SQLi? [y/N]: " enum_sql
    if [[ "$enum_sql" == "y" || "$enum_sql" == "Y" ]]; then
        eval "$exploit_cmd --dbs" | grep -v "^\["
        
        echo -e "\e[1;33m[+] Paste DB Name:\e[0m"
        read db_name
        if [ -n "$db_name" ]; then
            eval "$exploit_cmd -D \"$db_name\" --tables" | grep -v "^\["
            echo -e "\e[1;33m[+] Paste Table Name:\e[0m"
            read table_name
            if [ -n "$table_name" ]; then
                echo -e "\e[1;34m[*] Dumping SQL Data...\e[0m"
                eval "$exploit_cmd -D \"$db_name\" -T \"$table_name\" --dump-format=CSV --dump" | grep -v "^\[" | sed '/^$/d' > "$sql_data"
                echo -e "\e[1;32m[+] SQL Data saved to $sql_data\e[0m"
            fi
        fi
    fi
}

# ===========================================
# 2. XSS Scanning Function
# ===========================================
run_xss_scan() {
    separator
    echo -e "\e[1;31m[*] Starting XSS Scan (XSSer)...\e[0m"
    
    # --- Logic الذكي (Auto Marker) ---
    if [[ "$target" != *"XSS"* ]]; then
        if [[ "$target" == *"?"* ]]; then
            base_url="${target%=*}"
            xss_target="${base_url}=XSS"
            echo -e "\e[1;33m[!] Target URL modified to include XSS marker:\e[0m $xss_target"
        else
            xss_target="$target"
            echo -e "\e[1;33m[!] No parameters found. Trying Wide-Attack (--Coo --Fp)...\e[0m"
        fi
    else
        xss_target="$target"
    fi
    # ------------------------------

    # تحديد الأمر النهائي
    if [[ "$target" == *"?"* ]]; then
        xss_cmd="xsser -u \"$xss_target\" --auto --Cw=2"
    else
        xss_cmd="xsser -u \"$target\" --Coo --Fp --Cw=2"
    fi
    
    echo "Running: $xss_cmd"
    
    # 1. التشغيل وحفظ اللوجز
    echo -e "\e[1;36m[*] Scanning... (Logs saved to file)\e[0m"
    eval "$xss_cmd" > "$xss_log" 2>&1
    
    # 2. تنظيف واستخراج البيانات (Organized)
    echo -e "\e[1;36m[*] Processing results...\e[0m"
    
    awk '
    {
        if (match($0, /\[[^]]{5,}\]/)) {
            payload = substr($0, RSTART+1, RLENGTH-2);
            if (length(payload) > 0 && !(payload in seen)) {
                seen[payload] = 1;
            }
        }
    }
    END {
        print "============================================================";
        print "         SUCCESSFUL XSS PAYLOADS EXTRACTED (NO DUPLICATES)";
        print "============================================================";
        n = asorti(seen, sorted);
        for (i = 1; i <= n; i++) {
            print "------------------------------------------------------------";
            print "PAYLOAD #" i ":";
            print sorted[i];
        }
        print "============================================================";
    }
    ' "$xss_log" > "$xss_payloads"
    
    # 3. عرض الملخص
    if [ -s "$xss_payloads" ]; then
        echo -e "\e[1;32m[+] Payloads extracted and organized!\e[0m"
        echo -e "\e[1;32m[+] Saved to: $xss_payloads\e[0m"
    else
        echo -e "\e[1;31m[-] No payloads extracted.\e[0m"
    fi
}

# ===========================================
# 3. Manual Browser Test Function (Safe & Step-by-Step)
# ===========================================
run_manual_test() {
    separator
    echo -e "\e[1;32m[*] Starting Manual Payload Verification (Safe Mode)...\e[0m"
    
    if [ ! -f "$xss_log" ]; then
        echo -e "\e[1;31m[-] Error: XSS log file not found ($xss_log).\e[0m"
        echo -e "\e[1;31m[-] Please run XSS Scanning first (Option 2 or 3).\e[0m"
        return
    fi

    separator
    echo -e "\e[1;33m[?] Choose testing mode:\e[0m"
    echo "1) Test one payload manually"
    echo "2) Test ALL payloads (One by one - Wait for Enter)"
    echo "3) Auto-Test Payloads (Browser + Confirm) - NEW"
    read test_choice

    if [[ "$test_choice" == "3" ]]; then
        echo -e "\e[1;33m[*] Auto-Testing payloads and saving only working ones...\e[0m"
        > "$xss_payloads"  # clear old file

        param_name="${target##*\?}"
        param_name="${param_name%%=*}"
        if [ -z "$param_name" ]; then param_name="cat"; fi

        grep -oP '\[\K[^\]]+' "$xss_log" | sort -u | while read -r payload; do
            [[ -z "$payload" ]] && continue
            encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload'''))")
            final_url="${target%%\?*}?${param_name}=${encoded}"

            separator
            echo -e "\e[1;36m[*] Testing:\e[0m $payload"
            echo -e "\e[1;34m[*] URL:\e[0m $final_url"

            if command -v xdg-open &> /dev/null; then
                nohup xdg-open "$final_url" >/dev/null 2>&1 &
            elif command -v firefox &> /dev/null; then
                nohup firefox "$final_url" >/dev/null 2>&1 &
            fi

            echo -e "\e[1;33m[?] Did the payload work? (y/N):\e[0m"
            read -r confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                echo "$payload" >> "$xss_payloads"
                echo -e "\e[1;32m[+] Saved to Successful_Payloads.txt\e[0m"
            else
                echo -e "\e[1;31m[-] Skipped.\e[0m"
            fi
        done

        echo -e "\e[1;32m[+] Auto-test finished. Working payloads saved to:\e[0m $xss_payloads"
    else
        # keep old logic for 1 and 2
        param_name="${target##*\?}"
        param_name="${param_name%%=*}"
        if [ -z "$param_name" ]; then param_name="cat"; fi
        
        echo -e "\e[1;36m[*] Target Parameter: $param_name\e[0m"
        
        separator
        echo -e "\e[1;33m[?] Choose testing mode:\e[0m"
        echo "1) Test one payload manually"
        echo "2) Test ALL payloads (One by one - Wait for Enter)"
        read test_choice
        
        if [[ "$test_choice" == "1" ]]; then
            echo "Payloads:"
            tail -n +5 "$xss_payloads" 2>/dev/null | grep -v "^-\|^=" || echo "No payloads found."
            read -p "Enter Payload to test: " payload_text
            
            if [ -n "$payload_text" ]; then
                encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload_text'''))")
                final_url="${target%%\?*}?${param_name}=${encoded}"
                
                echo -e "\e[1;32m[*] Opening: $final_url\e[0m"
                if command -v xdg-open &> /dev/null; then
                    xdg-open "$final_url"
                elif command -v firefox &> /dev/null; then
                    firefox "$final_url"
                else
                    echo "$final_url"
                fi
            fi
            
        elif [[ "$test_choice" == "2" ]]; then
            read -p "This will test payloads one by one. Are you sure? [y/N]: " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                echo -e "\e[1;33m[*] Starting...\e[0m"
                
                current_payload=""
                count=0
                
                while IFS= read -r line; do
                    if [[ "$line" == *"------------------------------------------------------------"* ]]; then
                        if [ -n "$current_payload" ]; then
                            count=$((count+1))
                            separator
                            echo -e "\e[1;31m[*] Testing Payload #$count\e[0m"
                            echo -e "\e[1;36m[*] Payload: $current_payload\e[0m"
                            
                            encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$current_payload'''))")
                            final_url="${target%%\?*}?${param_name}=${encoded}"
                            
                            if command -v xdg-open &> /dev/null; then
                                nohup xdg-open "$final_url" >/dev/null 2>&1 &
                            elif command -v firefox &> /dev/null; then
                                nohup firefox "$final_url" >/dev/null 2>&1 &
                            fi
                            
                            echo -e "\e[1;33m[!] Check the browser tab for a Popup.\e[0m"
                            echo -e "\e[1;34m--- Press Enter to test next payload (Ctrl+C to stop) ---\e[0m"
                            read -r dummy
                            
                            current_payload=""
                        fi
                    else
                        if [[ "$line" != "PAYLOAD #"* ]] && [[ "$line" != *"PAYLOADS EXTRACTED"* ]] && [[ "$line" != *"======"* ]]; then
                            current_payload="$current_payload$line"
                        fi
                    fi
                done < "$xss_payloads"
                
                echo -e "\e[1;32m[+] All finished.\e[0m"
            fi
        fi
    fi
}

# ===========================================
# Menu System
# ===========================================
separator
echo -e "\e[1;34m[?] Select Scan Mode:\e[0m"
echo "1) SQL Injection Only"
echo "2) XSS Scanning Only"
echo "3) Full Scan (SQLi + XSS)"
echo "4) Test Validated Payloads (Browser)"
read choice

case $choice in
    1)
        run_sql_scan
        ;;
    2)
        run_xss_scan
        ;;
    3)
        run_sql_scan
        separator
        run_xss_scan
        ;;
    4)
        run_manual_test
        ;;
    *)
        echo -e "\e[1;31m[!] Invalid choice.\e[0m"
        exit 1
        ;;
esac

separator
echo -e "\e[1;32m[+] Operation Finished.\e[0m"
