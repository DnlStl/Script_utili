#!/bin/bash

# --- CONFIGURAZIONE COLORI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- LOGICA DI CORREZIONE ---

# 1. Filtri Locali (Regex e Pulizia Meccanica)
apply_local_filters() {
    local text="$1"
    # Riduce triple lettere o più (es: ciaooo -> ciao)
    text=$(echo "$text" | sed -E 's/([a-zA-Z])\1{2,}/\1/g')
    # Riduce doppie finali sospette (es: ciaoo -> ciao)
    text=$(echo "$text" | sed -E 's/([^ezo])\1+$/\1/gI')
    echo "$text"
}

# 2. Controllo Ortografico Ibrido (Anti-Cimiciaio Edition)
check_local_spelling() {
    local text="$1"
    local lang="$2"
    local final_text=""
    
    local dict="it_IT"
    [[ "$lang" == "en" ]] && dict="en_US"

    # MAPPA DI EMERGENZA (Priority 1)
    # Qui inseriamo le parole che i dizionari correggono male
    declare -A emergency_map=(
        ["ciaoaioai"]="ciao" 
        ["cioaio"]="ciao" 
        ["ciaoo"]="ciao"
        ["coem"]="come"
        ["km"]="come"
        ["nn"]="non"
        ["cmq"]="comunque"
    )

    read -r -a words <<< "$text"
    for word in "${words[@]}"; do
        clean_word=$(echo "$word" | sed 's/[^a-zA-ZàèéìòùÀÈÉÌÒÙ]//g')
        punct=$(echo "$word" | sed 's/[a-zA-ZàèéìòùÀÈÉÌÒÙ]//g')
        lower_word=$(echo "$clean_word" | tr '[:upper:]' '[:lower:]')

        suggestion=""

        # LIVELLO A: Controllo diretto in mappa
        if [[ -n "${emergency_map[$lower_word]}" ]]; then
            suggestion="${emergency_map[$lower_word]}"
        
        # LIVELLO B: Riconoscimento radice (Se contiene "ciao" o "come")
        elif [[ "$lower_word" == *ciao* ]]; then
            suggestion="ciao"
        elif [[ "$lower_word" == *come* ]]; then
            suggestion="come"

        # LIVELLO C: Hunspell con Filtro di Sicurezza
        elif [[ ${#clean_word} -gt 2 ]]; then
            # Chiediamo i suggerimenti a Hunspell
            first_sug=$(echo "$clean_word" | hunspell -d "$dict" -a 2>/dev/null | grep "&" | awk -F': ' '{print $2}' | awk -F', ' '{print $1}')
            
            if [[ -n "$first_sug" ]]; then
                # Filtro "Anti-Parola-Rara": se il suggerimento è troppo lungo o strano, lo scartiamo
                if [[ ${#first_sug} -gt $(( ${#clean_word} + 3 )) ]]; then
                    suggestion="$clean_word"
                else
                    suggestion="$first_sug"
                fi
            fi
        fi

        # Ricostruzione con punteggiatura originale
        if [[ -n "$suggestion" ]]; then
            final_text+="${suggestion}${punct} "
        else
            final_text+="${word} "
        fi
    done
    echo "$final_text" | xargs
}

# 3. Analisi Grammaticale (LanguageTool API)
call_languagetool() {
    curl -sX POST "https://api.languagetool.org/v2/check" \
        -d "text=$1" \
        -d "language=$2"
}

# --- PROCESSO PRINCIPALE ---

solve_all() {
    local input="$1"
    local lang_choice="$2"
    local lang_code="it-IT"
    local h_lang="it"
    [[ "$lang_choice" == "2" ]] && { lang_code="en-US"; h_lang="en"; }

    echo -e "${CYAN}[1/3] Pulizia meccanica...${NC}"
    local step1=$(apply_local_filters "$input")

    echo -e "${CYAN}[2/3] Controllo ortografico locale (Hybrid)...${NC}"
    local step2=$(check_local_spelling "$step1" "$h_lang")

    echo -e "${CYAN}[3/3] Analisi grammaticale profonda (Cloud)...${NC}"
    local api_res=$(call_languagetool "$step2" "$lang_code")
    
    local final_output="$step2"
    local matches=$(echo "$api_res" | jq '.matches | length')

    echo -e "\n${BLUE}=== RIEPILOGO ANALISI ===${NC}"
    printf "| %-20s | %-20s | %-30s |\n" "Originale" "Corretto" "Tipo Errore"
    echo "---------------------------------------------------------------------------------------"
    
    # Visualizziamo fix locali
    if [[ "$input" != "$step2" ]]; then
        printf "| ${YELLOW}%-18s${NC} | ${GREEN}%-18s${NC} | %-30s |\n" "${input:0:20}" "${step2:0:20}" "Ortografia/Digitazione"
    fi

    # Visualizziamo fix grammaticali
    if [[ "$matches" -gt 0 ]]; then
        for (( i=$((matches-1)); i>=0; i-- )); do
            local offset=$(echo "$api_res" | jq ".matches[$i].offset")
            local len=$(echo "$api_res" | jq ".matches[$i].length")
            local err=${step2:$offset:$len}
            local sug=$(echo "$api_res" | jq -r ".matches[$i].replacements[0].value")
            local msg=$(echo "$api_res" | jq -r ".matches[$i].message")
            
            if [[ "$sug" != "null" && "$sug" != "" ]]; then
                printf "| ${RED}%-18s${NC} | ${GREEN}%-18s${NC} | %-30s |\n" "$err" "$sug" "Grammatica"
                final_output="${final_output:0:$offset}$sug${final_output:$((offset+len))}"
            fi
        done
    fi
    echo "---------------------------------------------------------------------------------------"

    echo -e "\n${BLUE}TESTO REVISIONATO FINALE:${NC}"
    echo -e "${GREEN}$final_output${NC}\n"
}

# --- AVVIO SCRIPT ---
clear
echo -e "${BLUE}=== OMNI-CORRETTORE v4.5 (ULTIMATE DSA ENGINE) ===${NC}"

# Verifica dipendenze
for cmd in curl jq hunspell; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Errore: Installa $cmd (sudo apt install curl jq hunspell hunspell-it)${NC}"
        exit 1
    fi
done

read -p "Lingua (1:IT, 2:EN): " lc
read -p "Inserisci il testo: " ui

[[ -n "$ui" ]] && solve_all "$ui" "$lc"
