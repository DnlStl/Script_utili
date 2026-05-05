#!/bin/bash

# --- CONFIGURAZIONE COLORI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- FILE LOCALI ---
WHITELIST="nomi_cognomi.txt"
[[ ! -f "$WHITELIST" ]] && touch "$WHITELIST"

# --- LOGICA DI CORREZIONE ---

# 1. Filtri Meccanici
apply_local_filters() {
    local text="$1"
    # Riduce triple lettere (ciaooo -> ciao)
    text=$(echo "$text" | sed -E 's/([a-zA-Z])\1{2,}/\1/g')
    # Riduce doppie finali non italiane
    text=$(echo "$text" | sed -E 's/([^ezo])\1+$/\1/gI')
    echo "$text"
}

# 2. Controllo Ortografico Ibrido (con Whitelist locale)
check_local_spelling() {
    local text="$1"
    local lang="$2"
    local final_text=""
    local dict="it_IT"
    [[ "$lang" == "en" ]] && dict="en_US"

    # Carica whitelist (nomi e termini tecnici)
    local whitelist_content=$(cat "$WHITELIST" | tr '[:upper:]' '[:lower:]')

    declare -A emergency_map=(
        ["ciaoaioai"]="ciao" ["cioaio"]="ciao" ["ciaoo"]="ciao"
        ["coem"]="come" ["km"]="come" ["nn"]="non" ["cmq"]="comunque"
    )

    read -r -a words <<< "$text"
    for word in "${words[@]}"; do
        clean_word=$(echo "$word" | sed 's/[^a-zA-ZàèéìòùÀÈÉÌÒÙ]//g')
        punct=$(echo "$word" | sed 's/[a-zA-ZàèéìòùÀÈÉÌÒÙ]//g')
        lower_word=$(echo "$clean_word" | tr '[:upper:]' '[:lower:]')
        suggestion=""

        # A: Mappa di emergenza
        if [[ -n "${emergency_map[$lower_word]}" ]]; then
            suggestion="${emergency_map[$lower_word]}"
        
        # B: Whitelist (evita "pomone")
        elif [[ "$whitelist_content" == *"$lower_word"* ]]; then
            suggestion="$clean_word"

        # C: Radici comuni
        elif [[ "$lower_word" == *ciao* ]]; then
            suggestion="ciao"

        # D: Hunspell con protezione distanze
        elif [[ ${#clean_word} -gt 2 ]]; then
            first_sug=$(echo "$clean_word" | hunspell -d "$dict" -a 2>/dev/null | grep "&" | awk -F': ' '{print $2}' | awk -F', ' '{print $1}')
            if [[ -n "$first_sug" ]]; then
                # Se il suggerimento è troppo assurdo, tieni l'originale
                [[ ${#first_sug} -gt $(( ${#clean_word} + 3 )) ]] && suggestion="$clean_word" || suggestion="$first_sug"
            fi
        fi

        [[ -n "$suggestion" ]] && final_text+="${suggestion}${punct} " || final_text+="${word} "
    done
    echo "$final_text" | xargs
}

# 3. Analisi Grammaticale Cloud
call_languagetool() {
    curl -sX POST "https://api.languagetool.org/v2/check" -d "text=$1" -d "language=$2"
}

# --- FUNZIONE PRINCIPALE ---

solve_all() {
    local input="$1"
    local mode="$2"
    local lang_code="it-IT"

    local step1=$(apply_local_filters "$input")
    local step2=$(check_local_spelling "$step1" "it")
    local api_res=$(call_languagetool "$step2" "$lang_code")
    local final_output="$step2"
    local matches=$(echo "$api_res" | jq '.matches | length')

    if [[ "$matches" -gt 0 ]]; then
        for (( i=$((matches-1)); i>=0; i-- )); do
            local offset=$(echo "$api_res" | jq ".matches[$i].offset")
            local len=$(echo "$api_res" | jq ".matches[$i].length")
            local sug=$(echo "$api_res" | jq -r ".matches[$i].replacements[0].value")
            if [[ "$sug" != "null" && "$sug" != "" ]]; then
                final_output="${final_output:0:$offset}$sug${final_output:$((offset+len))}"
            fi
        done
    fi

    if [[ "$mode" == "clip" ]]; then
        echo "$final_output" | xclip -selection clipboard
        command -v notify-send >/dev/null && notify-send "Omni-Correttore" "Testo corretto e pronto in clipboard!"
        echo -e "${GREEN}Copiato negli appunti: $final_output${NC}"
    else
        echo -e "\n${BLUE}RISULTATO:${NC} ${GREEN}$final_output${NC}"
        # Creazione tabella riepilogativa
        echo -e "\n| Tipo | Valore |"
        echo "| :--- | :--- |"
        echo "| Input | $input |"
        echo "| Output | $final_output |"
    fi
}

# --- GESTIONE ARGOMENTI ---

clear
echo -e "${BLUE}=== OMNI-CORRETTORE v5.1 (Smart Engine) ===${NC}"

case "$1" in
    "--learn")
        if [[ -n "$2" ]]; then
            echo "$2" >> "$WHITELIST"
            echo -e "${GREEN}Imparato: '$2' non verrà più corretto.${NC}"
        else
            echo -e "${RED}Specifica la parola: --learn pokemon${NC}"
        fi
        ;;
    "--clip")
        CLIP_TEXT=$(xclip -selection clipboard -o 2>/dev/null)
        [[ -n "$CLIP_TEXT" ]] && solve_all "$CLIP_TEXT" "clip" || echo -e "${RED}Clipboard vuota!${NC}"
        ;;
    *)
        read -p "Inserisci testo: " ui
        [[ -n "$ui" ]] && solve_all "$ui" "manual"
        ;;
esac
