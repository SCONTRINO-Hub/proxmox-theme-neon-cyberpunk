#!/bin/bash
# install_theme_proxmox.sh : thème néon « cyberpunk » pour l'interface web de Proxmox VE 8 et 9.
# Fond sombre animé, VM colorées selon leur état, badge dans la barre du haut ; en option, un
# message d'accueil après la connexion et le retrait de la fenêtre « No valid subscription ».
# Damien SCONTRINO, BTS SIO, lycée Louis Armand (Nogent-sur-Marne). V29, octobre 2026.
# Licence CC BY-NC-SA 4.0. Police Orbitron : SIL Open Font License 1.1 (texte en fin de fichier).
# Usage, en root : ./install_theme_proxmox.sh (menu), ou ./install_theme_proxmox.sh --aide
# Fichier abîmé par un transfert depuis Windows (fins de ligne CRLF) : on le dit tout de suite.
# Chaque ligne de ce test finit par « # » : ainsi, il fonctionne même sur un fichier abîmé.
if [ -f "$0" ] && grep -q "$(printf '\r')" "$0" 2>/dev/null; then #
    printf '%s\n' "Erreur : $0 a des fins de ligne Windows (CRLF), sans doute à cause d'un transfert." >&2 #
    printf '%s\n' "Pour le réparer : sed -i 's/\r\$//' $0" >&2 #
    exit 1 #
fi #

# Lancé par « sh install_theme_proxmox.sh » : on se relance avec bash
if [ -z "$BASH_VERSION" ]; then
    [ -f "$0" ] && exec bash "$0" "$@"
    echo "Erreur : lancez ce script avec bash." >&2
    exit 1
fi
set -u

VERSION_THEME="V29 (révision du 16/10/2026)"

# Réglages proposés à la première installation ; ensuite, ce sont les réglages en place qui comptent
BADGE="%NODE%"                            # %NODE% (ou %NOEUD%) est remplacé par le nom du nœud
TITRE_MESSAGE="Message de l'enseignant"   # titre de la fenêtre du message d'accueil

# Fichiers concernés. RACINE, vide d'habitude, préfixe tous les chemins : elle sert aux essais.
RACINE="${RACINE:-}"
INDEX="$RACINE/usr/share/pve-manager/index.html.tpl"
CSS="$RACINE/usr/share/pve-manager/css/theme-proxmox-cyberpunk.css"
JS="$RACINE/usr/share/pve-manager/js/theme-proxmox-cyberpunk.js"
LIB="$RACINE/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
SOMBRE="$RACINE/usr/share/javascript/proxmox-widget-toolkit/themes/theme-proxmox-dark.css"
SAUVEGARDES="$RACINE/var/backups/theme-proxmox-cyberpunk"
MARQUE="theme-proxmox-cyberpunk"          # repère nos lignes dans index.html.tpl
VERROU="$RACINE/run/theme-proxmox-cyberpunk.verrou"
# Remise automatique après une mise à jour (en option) : un crochet APT, et la copie du script qu'il lance
CROCHET="$RACINE/etc/apt/apt.conf.d/99-theme-proxmox-cyberpunk"
COPIE="$RACINE/usr/local/sbin/theme-proxmox-cyberpunk"

# Retrait de la fenêtre d'abonnement, dans Proxmox.Utils.checked_command de proxmoxlib.js :
# « Ext.Msg.show({ title: gettext('No valid subscription'), … callback: … orig_cmd(); }) » devient
# « orig_cmd(), void({ //Ext.Msg.show({ … » : la fenêtre ne s'ouvre plus et l'action demandée (Refresh des
# mises à jour, Package versions, System Report, ajout d'un dépôt) est lancée tout de suite.
# Un simple « void({ // » (ancienne méthode, encore courante) supprime aussi l'action : ces boutons ne font
# alors plus rien. AVEC_FENETRE enlève l'une ou l'autre forme (même répétée) et rend le fichier d'origine.
AVANT_FENETRE='(?=Ext\.Msg\.show\(\{\s+title: gettext\(.No valid subscription.\),)'
SANS_FENETRE='s/'"$AVANT_FENETRE"'/orig_cmd(), void({ \/\//g'
AVEC_FENETRE='s/(?:(?:orig_cmd\(\), )?void\(\{ \/\/)+'"$AVANT_FENETRE"'//g'
REPERE='void({ //Ext.Msg.show'              # fenêtre retirée (par ce script ou par un autre outil)
REPERE_OK='orig_cmd(), void({ //Ext.Msg.show'

umask 022
ROUGE="" NORMAL=""
if [ -t 2 ]; then ROUGE=$'\e[31m' NORMAL=$'\e[0m'; fi

# (le programme principal est tout en bas, après le CSS et la police)

erreur() {
    echo "${ROUGE}Erreur : $*${NORMAL}" >&2
    exit 1
}

aide() {
    cat <<EOF
Usage (en root) : $0 [options]

Sans option, un menu s'affiche. Sinon :
  --installer             installe ou met à jour le thème, sans poser de question ;
                          les réglages en place (badge, message, fenêtre, mises à jour) sont gardés
    --badge "TEXTE"       texte du badge ; %NODE% = nom du nœud (par défaut : %NODE%)
    --message FICHIER     message d'accueil affiché après la connexion (fichier .html ou texte)
    --sans-message        retire le message d'accueil
    --sans-abonnement     retire la fenêtre « No valid subscription »
    --avec-abonnement     remet cette fenêtre
    --auto-maj            remet le thème tout seul quand Proxmox met à jour son interface
    --sans-auto-maj       ne le remet pas : il faudra relancer ce script après une mise à jour
    --silencieux          n'affiche rien (c'est ainsi que la remise automatique le lance)
  --desinstaller          retire le thème et remet les fichiers d'origine
  --version               affiche la version et l'empreinte du script

Exemple : $0 --installer --badge "%NODE% - Lycée Exemple" --message accueil.html

Ensuite, rafraîchissez la page du navigateur (Ctrl+F5) : aucun service n'est redémarré.
À lancer sur chaque nœud du cluster. Quand Proxmox met à jour son interface, le thème
disparaît : avec --auto-maj, il revient tout seul après la mise à jour (faite par apt ou
depuis l'interface web) ; sinon, relancez le script, qui reprend les réglages en place.
Les options de la V28 --auto, --install, --uninstall et --no-sub sont encore acceptées.
EOF
}

verifier() {
    [ "$EUID" -eq 0 ] || erreur "ce script se lance en root."
    command -v pveversion >/dev/null || erreur "ce serveur n'est pas un Proxmox VE (pveversion introuvable)."
    VERSION_PVE=$(pveversion | cut -d/ -f2)    # « pve-manager/9.2.20/… » → 9.2.20
    NOEUD=$(hostname -s)
    [ -f "$INDEX" ] || erreur "$INDEX introuvable."
}

# Les réglages en place deviennent les réglages par défaut (menu et --installer)
reglages_actuels() {
    local actuel conf_v28 nom
    # Le badge tel qu'il a été demandé (avec %NODE%) est noté dans le CSS ; à défaut, on prend le texte affiché
    actuel=$(sed -n 's|^ \* Modèle du badge : \(.*\) \*/$|\1|p' "$CSS" 2>/dev/null | head -n 1)
    if [ -z "$actuel" ]; then
        actuel=$(grep -A1 '^#versioninfo-innerCt::before {' "$CSS" 2>/dev/null \
            | sed -n 's/^ *content: "\(.*\)" !important;$/\1/p')
        # Installé par une version qui ne notait pas le modèle : le nom du nœud redevient %NODE%
        nom=$(hostname -s 2>/dev/null) || nom=""
        if [ -n "$actuel" ] && [ -n "$nom" ]; then actuel=${actuel//"$nom"/%NODE%}; fi
    fi
    if [ -n "$actuel" ]; then BADGE=$actuel; fi
    if [ -f "$JS" ]; then GARDER_MESSAGE=1; fi
    # Fenêtre retirée par ce script (copie d'origine gardée, ou nouvelle forme), ou par la V28 (son theme.conf).
    # Un retrait fait par un autre outil n'est pas repris d'office : le menu propose de s'en charger.
    conf_v28="$RACINE/opt/theme-proxmox-cyberpunk/theme.conf"
    if [ -f "$SAUVEGARDES/proxmoxlib.js" ] || grep -qsF "$REPERE_OK" "$LIB" \
        || grep -qsE '^CONF_(SANS_ABO(NNEMENT)?|ABO(NNEMENT)?_PAR_SCRIPT)=1' "$conf_v28"; then
        SANS_ABONNEMENT=1
    fi
    # Remise automatique : « non » par défaut ; un crochet qui lance la copie du script veut dire « oui »
    if grep -qsF "${COPIE#"$RACINE"} --installer" "$CROCHET"; then AUTO_MAJ=1; fi
}

# Un message d'accueil se lit dans un fichier non vide (ou un flux), jamais dans un dossier
message_lisible() {
    [ -r "$1" ] && [ ! -d "$1" ] && { [ ! -f "$1" ] || [ -s "$1" ]; }
}

# Texte lu sur l'entrée standard → chaîne JavaScript entre guillemets, sans danger pour la page
en_js() {
    perl -MJSON::PP -e 'local $/; my $s = <STDIN>; $s = "" unless defined $s; utf8::decode($s);
        my $j = JSON::PP->new->ascii->allow_nonref->encode($s); $j =~ s{</}{<\\/}g; print $j;'
}

# La feuille de style du thème, avec le badge et la police
ecrire_css() {
    local badge modele corps
    # Tapé depuis une console en Latin-1 (PuTTY), le badge arrive mal encodé : on le passe en UTF-8
    printf '%s' "$BADGE" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 \
        || BADGE=$(printf '%s' "$BADGE" | iconv -f ISO-8859-1 -t UTF-8)
    badge=${BADGE//%NODE%/$NOEUD}
    badge=${badge//%NOEUD%/$NOEUD}
    # Le badge est recopié entre guillemets dans le CSS : on en retire " et \
    badge=$(printf '%s' "$badge" | tr -d '"\\\n\r')
    badge=${badge//\*\//}
    # Le modèle (avec %NODE%) est gardé en commentaire : le badge suit un changement de nom du nœud
    modele=$(printf '%s' "$BADGE" | tr -d '\n\r' | sed 's|\*/||g')
    corps=$(feuille_de_style)
    corps=${corps//@@BADGE@@/"$badge"}
    corps=${corps//@@ORBITRON700@@/"$(police 700)"}
    corps=${corps//@@ORBITRON900@@/"$(police 900)"}
    {
        echo '@charset "UTF-8";'
        echo "/* Thème néon « cyberpunk » pour Proxmox VE (V29), Damien SCONTRINO, CC BY-NC-SA 4.0"
        echo " * Police Orbitron (c) 2018 The Orbitron Project Authors, SIL Open Font License 1.1"
        echo " * Fichier créé par install_theme_proxmox.sh : relancer le script pour le modifier."
        printf ' * Modèle du badge : %s */\n' "$modele"
        printf '%s\n' "$corps"
    } > "$CSS" || erreur "écriture de $CSS impossible."
    echo "Badge : $badge"
}

# Le script du message d'accueil (MESSAGE = fichier .html, ou texte brut mis en HTML)
ecrire_js() {
    local message titre cle js
    if [ "$GARDER_MESSAGE" = 1 ]; then
        echo "Message d'accueil : inchangé."
        return
    fi
    if [ -z "$MESSAGE" ]; then
        if [ -f "$JS" ]; then echo "Message d'accueil : retiré."; fi
        rm -f "$JS"
        return
    fi
    case "${MESSAGE,,}" in
        *.html|*.htm) message=$(en_js < "$MESSAGE") ;;
        # texte brut : caractères spéciaux neutralisés, retours à la ligne gardés
        *) message=$(perl -CSD -pe 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g; s/"/&quot;/g; s/\n/<br>\n/' "$MESSAGE" \
               | en_js) ;;
    esac
    titre=$(printf '%s' "$TITRE_MESSAGE" | en_js)
    # La clé change avec le message : un message modifié s'affiche de nouveau
    cle=$(printf '%s|%s' "$message" "$titre" | sha256sum | cut -c1-16)
    js=$(script_message)
    js=${js//@@CLE@@/\"$cle\"}
    js=${js//@@TITRE@@/"$titre"}
    js=${js//@@MESSAGE@@/"$message"}
    printf '%s\n' "$js" > "$JS" || erreur "écriture de $JS impossible."
    echo "Message d'accueil : $MESSAGE"
}

# Ajoute nos lignes juste avant </head> dans index.html.tpl, ou les retire.
# On repart toujours du fichier sans nos lignes : relancer ne les double jamais.
modifier_index() {   # $1 = ajouter ou retirer
    local lignes="" tmp="$INDEX.$MARQUE" lien version
    if [ "$1" = ajouter ]; then
        # Copie du fichier d'origine, refaite à chaque fois pour suivre les mises à jour de Proxmox
        mkdir -p "$SAUVEGARDES" || erreur "impossible de créer $SAUVEGARDES."
        grep -vF "$MARQUE" "$INDEX" > "$SAUVEGARDES/index.html.tpl" || erreur "copie de $INDEX impossible."
        # La base sombre de Proxmox d'abord (sans elle, boutons et champs restent clairs), puis le thème
        if [ -f "$SOMBRE" ]; then
            lien='<link rel="stylesheet" type="text/css" href="/pwt/themes/theme-proxmox-dark.css" />'
            lignes+="    $lien<!-- $MARQUE : base sombre de Proxmox, ajoute par install_theme_proxmox.sh -->"$'\n'
        fi
        version=$(sha256sum < "$CSS" | cut -c1-12)
        lien='<link rel="stylesheet" type="text/css" href="/pve2/css/theme-proxmox-cyberpunk.css?v='$version'" />'
        lignes+="    $lien<!-- $MARQUE : ajoute par install_theme_proxmox.sh -->"$'\n'
        if [ -f "$JS" ]; then
            version=$(sha256sum < "$JS" | cut -c1-12)
            lien='<script type="text/javascript" src="/pve2/js/theme-proxmox-cyberpunk.js?v='$version'"></script>'
            lignes+="    $lien<!-- $MARQUE : ajoute par install_theme_proxmox.sh -->"$'\n'
        fi
    elif ! grep -qF "$MARQUE" "$INDEX"; then
        return   # rien à retirer
    fi
    LIGNES="$lignes" awk -v marque="$MARQUE" '
        index($0, marque) { next }                        # nos lignes déjà présentes
        /<\/head>/ { printf "%s", ENVIRON["LIGNES"] }     # les nouvelles, avant </head>
        { print }' "$INDEX" > "$tmp"
    # On ne remplace l'original que par un fichier complet
    if ! grep -q '</html>' "$tmp"; then
        rm -f "$tmp"
        erreur "$INDEX : fichier produit incomplet, l'original n'est pas modifié."
    fi
    mv -f "$tmp" "$INDEX" || erreur "écriture de $INDEX impossible."
}

# Retire ou remet la fenêtre « No valid subscription ». La copie d'origine de proxmoxlib.js est gardée dans
# $SAUVEGARDES. Pour remettre la fenêtre, on enlève seulement notre ajout : les autres retouches restent.
# Si la fenêtre avait déjà été retirée par un autre outil (ancienne forme), ce script la reprend avec la bonne
# forme, et la désinstallation la laisse retirée, comme avant le thème.
abonnement() {   # $1 = verifier, retirer, remettre ; $2 = desinstallation (pour remettre)
    local sauv="$SAUVEGARDES/proxmoxlib.js" avant="$SAUVEGARDES/retrait-avant-theme" tmp="$LIB.$MARQUE"
    case "$1" in
    verifier)   # avant toute écriture : la modification est-elle possible sur ce fichier ? (code de retour)
        ! grep -q "No valid subscription" "$LIB" || grep -qF "$REPERE_OK" "$LIB" \
            || perl -0777 -pe "$AVEC_FENETRE" "$LIB" | perl -0777 -pe "$SANS_FENETRE" | grep -qF "$REPERE_OK"
        ;;
    retirer)
        if grep -qF "$REPERE_OK" "$LIB"; then
            # La copie d'origine est refaite si elle manque : le choix survit ainsi aux mises à jour
            if [ ! -f "$sauv" ]; then
                mkdir -p "$SAUVEGARDES" || erreur "impossible de créer $SAUVEGARDES."
                perl -0777 -pe "$AVEC_FENETRE" "$LIB" > "$sauv" || erreur "copie de $LIB impossible."
            fi
            echo "Fenêtre « No valid subscription » : déjà retirée."
            return
        fi
        if ! grep -q "No valid subscription" "$LIB"; then
            echo "Fenêtre « No valid subscription » introuvable dans proxmoxlib.js : rien n'est changé."
            return
        fi
        mkdir -p "$SAUVEGARDES" || erreur "impossible de créer $SAUVEGARDES."
        # Retrait fait avant le thème par un autre outil : on s'en souvient pour la désinstallation
        if [ ! -f "$sauv" ] && grep -qF "$REPERE" "$LIB"; then : > "$avant"; fi
        # Copie d'origine ; si l'ancienne méthode était en place, on l'enlève d'abord pour retrouver l'original
        if ! { perl -0777 -pe "$AVEC_FENETRE" "$LIB" > "$sauv.tmp" && mv -f "$sauv.tmp" "$sauv"; }; then
            erreur "copie de $LIB impossible."
        fi
        if grep -qF "$REPERE" "$LIB"; then
            echo "Ancien retrait de la fenêtre remplacé : il bloquait aussi des boutons (Mises à jour, Dépôts…)."
        fi
        perl -0777 -pe "$SANS_FENETRE" "$sauv" > "$tmp"
        if [ "$(grep -cF "$REPERE_OK" "$tmp")" != 1 ]; then
            rm -f "$tmp"
            erreur "modification de proxmoxlib.js anormale : l'original n'est pas modifié."
        fi
        mv -f "$tmp" "$LIB" || erreur "écriture de $LIB impossible."
        echo "Fenêtre « No valid subscription » retirée (fichier d'origine gardé dans $SAUVEGARDES)."
        ;;
    remettre)
        if [ ! -f "$sauv" ]; then
            if grep -qsF "$REPERE" "$LIB" && ! grep -qsF "$REPERE_OK" "$LIB"; then
                echo "Fenêtre « No valid subscription » retirée par un autre outil, avec une ancienne méthode"
                echo "qui bloque aussi des boutons (Mises à jour, Dépôts…). Elle est laissée ainsi ; pour que ce"
                echo "script la retire correctement, répondez o à la question du menu, ou ajoutez --sans-abonnement."
            fi
            return
        fi
        if [ "${2:-}" = desinstallation ] && [ -f "$avant" ] && grep -qF "$REPERE_OK" "$LIB"; then
            # Retirée avant le thème : elle le reste, avec la bonne méthode
            rm -f "$sauv" "$avant"
            echo "Fenêtre « No valid subscription » laissée retirée, comme avant le thème (les boutons fonctionnent)."
            return
        fi
        if grep -qF "$REPERE" "$LIB"; then
            if ! perl -0777 -pe "$AVEC_FENETRE" "$LIB" > "$tmp" || grep -qF "$REPERE" "$tmp"; then
                rm -f "$tmp"
                erreur "remise de $LIB impossible (copie d'origine gardée : $sauv)."
            fi
            mv -f "$tmp" "$LIB" || erreur "écriture de $LIB impossible (copie d'origine gardée : $sauv)."
            if cmp -s "$LIB" "$sauv"; then
                echo "Fenêtre « No valid subscription » remise."
            else
                echo "Ajout de ce script retiré de proxmoxlib.js, qui garde les retouches d'un autre outil."
            fi
        fi
        rm -f "$sauv" "$avant"
        ;;
    *) erreur "abonnement : action inconnue ($1)." ;;
    esac
}

# Remise automatique après une mise à jour de Proxmox. Le crochet est une commande « DPkg::Post-Invoke » :
# apt la lance après chaque passage de dpkg (installation, mise à jour, suppression, réussi ou non).
# Elle relance une copie de ce script en mode silencieux, qui s'arrête tout de suite si le thème est
# en place ; s'il y a un souci, elle se tait, et apt n'échoue jamais à cause d'elle (« || true »).
# Elle ne lance ni apt ni dpkg : elle ne peut donc pas se redéclencher elle-même.
# « DPkg::Post-Invoke-Success » n'existe pas (seulement APT::Update::Post-Invoke-Success) : apt l'ignorerait.
remise_auto() {   # $1 = poser ou retirer
    local chemin=${COPIE#"$RACINE"}   # chemin réel de la copie (RACINE ne sert qu'aux essais)
    if [ "$1" = retirer ]; then
        if [ -e "$CROCHET" ] || [ -e "$COPIE" ]; then
            rm -f "$CROCHET" "$COPIE"
            echo "Remise automatique après les mises à jour : retirée."
        fi
        return
    fi
    # La copie du script, remplacée d'un bloc (mv) : jamais réécrite pendant qu'elle tourne
    if ! [ "$0" -ef "$COPIE" ]; then
        if ! { cp "$0" "$COPIE.tmp" && chmod 755 "$COPIE.tmp" && mv -f "$COPIE.tmp" "$COPIE"; }; then
            rm -f "$COPIE.tmp"
            erreur "copie du script dans $COPIE impossible."
        fi
    fi
    # Le crochet est écrit à côté, puis mis en place d'un bloc : apt ne lit jamais un fichier
    # à moitié écrit (il ignore les noms qui finissent par « ~ »)
    if ! cat > "$CROCHET~" <<FIN_CROCHET
// Thème néon pour Proxmox : quand Proxmox met à jour son interface, le thème disparaît,
// et ce fichier le remet juste après. Posé par install_theme_proxmox.sh, qui le retire
// à la désinstallation, ou si l'on répond « n » à sa question (--sans-auto-maj).
// Après chaque passage d'apt, il relance la copie du script sans rien afficher : elle
// s'arrête tout de suite si le thème est en place, se tait en cas de souci, et apt
// n'échoue jamais à cause d'elle.
DPkg::Post-Invoke { "$chemin --installer --silencieux </dev/null >/dev/null 2>&1 || true"; };
FIN_CROCHET
    then
        rm -f "$CROCHET~"
        erreur "écriture de $CROCHET impossible."
    fi
    mv -f "$CROCHET~" "$CROCHET" || erreur "écriture de $CROCHET impossible."
    echo "Remise automatique après les mises à jour : activée (${CROCHET#"$RACINE"})."
}

# Retire ce qu'une version 28 a pu laisser : son dossier /opt, son journal, et son crochet APT
# (il porte le même nom que le nôtre, mais lance la copie de /opt, et apt ne l'exécutait pas).
nettoyer_v28() {
    local opt="$RACINE/opt/theme-proxmox-cyberpunk"
    local journal="$RACINE/var/log/theme-proxmox-cyberpunk.log"
    local crochet_v28=0
    if grep -qs /opt/theme-proxmox-cyberpunk "$CROCHET"; then crochet_v28=1; fi
    [ "$crochet_v28" = 1 ] || [ -e "$opt" ] || [ -e "$journal" ] || return 0
    # Si la V28 avait retiré la fenêtre d'abonnement, on reconstitue la copie d'origine de proxmoxlib.js :
    # la suite la remettra, ou la retirera de nouveau avec la bonne méthode.
    if grep -qsE '^CONF_ABO(NNEMENT)?_PAR_SCRIPT=1' "$opt/theme.conf" && [ ! -f "$SAUVEGARDES/proxmoxlib.js" ]; then
        mkdir -p "$SAUVEGARDES" || erreur "impossible de créer $SAUVEGARDES."
        perl -0777 -pe "$AVEC_FENETRE" "$LIB" > "$SAUVEGARDES/proxmoxlib.js" || erreur "copie de $LIB impossible."
    fi
    # Son message d'accueil n'existait que dans /opt : on le met de côté
    if [ -f "$opt/message.html" ]; then
        cp "$opt/message.html" "$RACINE/root/message_accueil_v28.html"
        echo "Message d'accueil de la V28 mis de côté : /root/message_accueil_v28.html"
    fi
    if [ "$crochet_v28" = 1 ]; then rm -f "$CROCHET"; fi
    rm -rf "$opt" "$journal" "$RACINE/run/theme-proxmox-cyberpunk.lock"
    if [ "$crochet_v28" = 1 ]; then
        echo "Restes de la version 28 retirés : crochet APT (inopérant), /opt/theme-proxmox-cyberpunk et journal."
    else
        echo "Restes de la version 28 retirés : /opt/theme-proxmox-cyberpunk et journal."
    fi
}

# Un seul lancement à la fois : la remise automatique peut passer pendant qu'on lance le script à la main.
# Le verrou est pris juste avant d'écrire (après les questions du menu), dans /run, réservé à root.
verrouiller() {
    mkdir -p "${VERROU%/*}" || erreur "impossible de créer ${VERROU%/*}."
    exec 9>"$VERROU" || erreur "verrou $VERROU impossible."
    flock -w 120 9 || erreur "un autre lancement de ce script est en cours (verrou $VERROU)."
}

# Les sauvegardes des anciennes versions ne sont jamais supprimées par ce script : on le rappelle
anciennes_sauvegardes() {
    [ -d "$RACINE/root/sauvegardes-theme-proxmox" ] || return 0
    echo "Les sauvegardes des anciennes versions du thème restent dans /root/sauvegardes-theme-proxmox :"
    echo "ce script n'y touche pas, supprimez ce dossier vous-même quand il ne vous sert plus."
}

# Rappel pour un cluster : chaque nœud sert sa propre interface
rappel_cluster() {
    if [ -f "$RACINE/etc/pve/corosync.conf" ]; then
        echo "Nœud en cluster : lancez aussi ce script sur les autres nœuds."
    fi
}

installer() {
    case "$VERSION_PVE" in
        8.*|9.*) ;;
        *) erreur "ce script est prévu pour Proxmox VE 8 et 9 (version trouvée : $VERSION_PVE)." ;;
    esac
    if [ "$(grep -o '</head>' "$INDEX" | wc -l)" != 1 ]; then
        erreur "$INDEX inhabituel (</head> absent ou en double) : rien n'est modifié."
    fi
    # Tout ce qui peut échouer est vérifié avant la première écriture
    if [ -n "$MESSAGE" ] && ! message_lisible "$MESSAGE"; then
        erreur "fichier de message introuvable, vide ou illisible : $MESSAGE"
    fi
    if [ "$SANS_ABONNEMENT" = 1 ] && ! abonnement verifier; then
        if [ "$SILENCIEUX" != 1 ]; then
            erreur "proxmoxlib.js inhabituel : la fenêtre d'abonnement ne peut pas être retirée. Rien n'est modifié."
        fi
        # Lancé par apt après une mise à jour : on remet quand même le thème, sans toucher à proxmoxlib.js
        logger -t theme-proxmox-cyberpunk "proxmoxlib.js inhabituel : fenêtre d'abonnement laissée telle quelle" || true
        SANS_ABONNEMENT=garder
    fi
    if [ "$AUTO_MAJ" = 1 ]; then
        [ "$0" -ef "$COPIE" ] || [ -f "$0" ] \
            || erreur "la remise automatique demande un script lancé depuis un fichier (ou ajoutez --sans-auto-maj)."
        if [ ! -d "${COPIE%/*}" ] || [ ! -d "${CROCHET%/*}" ]; then
            erreur "${COPIE%/*} ou ${CROCHET%/*} absent : rien n'est modifié."
        fi
    fi
    verrouiller
    nettoyer_v28
    ecrire_css
    ecrire_js
    modifier_index ajouter
    case "$SANS_ABONNEMENT" in
        1) abonnement retirer ;;
        0) abonnement remettre ;;
        *) ;;   # « garder » : proxmoxlib.js inhabituel, laissé tel quel
    esac
    if [ "$AUTO_MAJ" = 1 ]; then remise_auto poser; else remise_auto retirer; fi
    echo "Thème installé sur $NOEUD."
    echo "Rafraîchissez la page du navigateur (Ctrl+F5) : aucun service n'est redémarré."
    if [ "$AUTO_MAJ" = 1 ]; then
        echo "Après une mise à jour de Proxmox, le thème revient tout seul."
    else
        echo "Après une mise à jour de Proxmox, relancez ce script."
    fi
    rappel_cluster
    anciennes_sauvegardes
}

desinstaller() {
    verrouiller
    nettoyer_v28
    if ! grep -qF "$MARQUE" "$INDEX" && [ ! -e "$CSS" ] && [ ! -e "$JS" ] && [ ! -e "$CROCHET" ] \
        && [ ! -e "$COPIE" ] && [ ! -e "$SAUVEGARDES" ]; then
        echo "Rien à retirer : le thème n'est pas installé sur $NOEUD."
        rm -f "$VERROU"
        anciennes_sauvegardes
        return
    fi
    remise_auto retirer
    modifier_index retirer
    abonnement remettre desinstallation
    if cmp -s "$INDEX" "$SAUVEGARDES/index.html.tpl"; then
        echo "index.html.tpl : identique à la copie d'origine."
    fi
    rm -f "$CSS" "$JS" "$SAUVEGARDES/index.html.tpl" "$VERROU"
    rmdir "$SAUVEGARDES" 2>/dev/null
    echo "Thème retiré de $NOEUD. Rafraîchissez la page du navigateur (Ctrl+F5)."
    anciennes_sauvegardes
}

# Pose une question (affichée même sans terminal, par exemple via ssh sans -t) et lit la réponse
demander() {   # $1 = variable, $2 = question
    printf '%s' "$2" >&2
    IFS= read -r "$1" || true
}

menu() {
    local choix rep defaut=n
    # Lu depuis un tube (curl … | bash), le script servirait lui-même de réponses aux questions
    if [ ! -t 0 ] && [ ! -f "$0" ]; then
        erreur "le menu a besoin d'un terminal : lancez le script depuis un fichier, ou utilisez --installer."
    fi
    echo "Thème néon pour Proxmox VE : nœud $NOEUD, Proxmox VE $VERSION_PVE"
    if grep -qF "$MARQUE" "$INDEX"; then
        echo "Le thème est installé."
    elif [ -f "$CSS" ]; then
        echo "Le thème n'est plus actif (mise à jour de Proxmox ?) : choisissez 1 pour le remettre."
    else
        echo "Le thème n'est pas installé."
    fi
    echo
    echo "  1) Installer ou mettre à jour"
    echo "  2) Désinstaller"
    echo "  0) Quitter"
    demander choix "Votre choix : "
    case "$choix" in
        1) ;;
        2) desinstaller; return ;;
        0|"") return ;;
        *) echo "Choix inconnu : rien n'est fait." >&2; return ;;
    esac
    # Les réponses par défaut sont les réglages en place : après une mise à jour de Proxmox,
    # il suffit d'appuyer sur Entrée à chaque question.
    demander rep "Texte du badge (%NODE% = nom du nœud) [$BADGE] : "
    if [ -n "$rep" ]; then BADGE=$rep; fi
    while :; do
        if [ "$GARDER_MESSAGE" = 1 ]; then
            demander rep "Message d'accueil : fichier .html ou .txt (Entrée = garder, « aucun » = retirer) : "
        else
            demander rep "Message d'accueil : fichier .html ou .txt (Entrée = aucun) : "
        fi
        case "$rep" in
            "") break ;;
            aucun) GARDER_MESSAGE=0 MESSAGE=""; break ;;
            *) ;;
        esac
        rep=${rep/#\~/${HOME:-/root}}
        if message_lisible "$rep"; then
            GARDER_MESSAGE=0 MESSAGE=$rep
            break
        fi
        echo "Fichier introuvable, vide ou illisible : $rep" >&2
        echo "(écrivez d'abord le message dans un fichier, puis donnez son chemin)" >&2
    done
    if [ "$SANS_ABONNEMENT" = 1 ]; then defaut=o; fi
    if [ "$SANS_ABONNEMENT" = 0 ] && grep -qsF "$REPERE" "$LIB"; then
        echo "La fenêtre « No valid subscription » a été retirée par un autre outil, avec une ancienne méthode qui"
        echo "bloque aussi des boutons (Mises à jour, Dépôts…). Répondez o pour que ce script s'en charge."
    fi
    demander rep "Retirer la fenêtre « No valid subscription » ? (o/n) [$defaut] : "
    case "${rep:-$defaut}" in
        [oOyY]*) SANS_ABONNEMENT=1 ;;
        *) SANS_ABONNEMENT=0 ;;
    esac
    defaut=n
    if [ "$AUTO_MAJ" = 1 ]; then defaut=o; fi
    echo "Quand Proxmox met à jour son interface, le thème disparaît (sans rien casser)."
    if [ ! -f "$0" ]; then
        # La remise automatique copie le script : impossible s'il n'est pas lancé depuis un fichier
        echo "Script lancé sans fichier : relancez-le après chaque mise à jour."
        AUTO_MAJ=0
    else
        echo "Si vous répondez non, il suffira de relancer ce script après la mise à jour."
        demander rep "Voulez-vous que le thème se remette tout seul après chaque mise à jour ? (o/n) [$defaut] : "
        case "${rep:-$defaut}" in
            [oOyY]*) AUTO_MAJ=1 ;;
            *) AUTO_MAJ=0 ;;
        esac
    fi
    installer
}

# --- Données : le CSS du thème, le JavaScript du message d'accueil et la police ---

feuille_de_style() {
cat <<'FIN_CSS'

/* Police Orbitron, intégrée en base64 : rien n'est téléchargé.
 * (c) 2018 The Orbitron Project Authors, SIL Open Font License 1.1 */

@font-face {
    font-family: 'Orbitron';
    font-weight: 700;
    font-display: swap;
    src: url(data:font/ttf;base64,@@ORBITRON700@@) format('truetype');
}

@font-face {
    font-family: 'Orbitron';
    font-weight: 900;
    font-display: swap;
    src: url(data:font/ttf;base64,@@ORBITRON900@@) format('truetype');
}


/* Fond : dégradé sombre et quelques points lumineux qui dérivent */

body {
    background: linear-gradient(135deg, #0a0e1a 0%, #0d1424 50%, #0a1220 100%) !important;
    background-attachment: fixed !important;
}

body::before {
    content: "";
    position: fixed;
    top: 0; left: 0; width: 100%; height: 100%;
    background-image:
        radial-gradient(2px 2px at 15% 25%, rgba(0,212,255,0.6), transparent 40%),
        radial-gradient(3px 3px at 85% 75%, rgba(0,180,255,0.5), transparent 40%),
        radial-gradient(2px 2px at 50% 50%, rgba(100,200,255,0.5), transparent 40%),
        radial-gradient(1px 1px at 30% 60%, rgba(0,230,255,0.7), transparent 30%),
        radial-gradient(2px 2px at 70% 30%, rgba(0,200,255,0.6), transparent 35%);
    animation: particlesFloat 25s linear infinite !important;
    pointer-events: none;
    z-index: 1;
    mix-blend-mode: screen;
}

@keyframes particlesFloat {
    0%   { transform: translateY(0) translateX(0); opacity: 0.7; }
    50%  { transform: translateY(-50px) translateX(30px); opacity: 1; }
    100% { transform: translateY(-100px) translateX(-20px); opacity: 0.7; }
}

body > * { position: relative; z-index: 2; }


/* Panneaux et grilles */

.x-panel-body, .x-panel-body-default,
.x-grid-item-container, .x-panel.x-grid,
.x-tree-view, .x-grid-body, .x-grid-view,
.x-fit-item, .x-panel-bodyWrap,
.x-docked-noborder-top, .x-docked-noborder-bottom,
.x-panel-default, .x-window-default {
    background: rgba(15,25,45,0.95) !important;
    background-color: rgba(15,25,45,0.95) !important;
}

.x-grid-item {
    background: transparent !important;
    border-bottom: 1px solid rgba(0,180,255,0.1) !important;
}
.x-grid-item:nth-child(even) {
    background: rgba(20,30,50,0.7) !important;
}

.x-grid-empty, div.x-grid-empty {
    background: rgba(15,25,45,0.95) !important;
    background-color: rgba(15,25,45,0.95) !important;
    color: #a0b8d0 !important;
}

.x-toolbar-default, .x-toolbar-footer {
    background: rgba(15,25,45,0.9) !important;
}
.x-tab-bar, .x-tab-bar-default {
    background: rgba(15,25,45,0.95) !important;
}

.install-mask, p.install-mask,
.x-window-body-install-mask, .x-panel-body-install-mask {
    background: rgba(15,25,45,0.95) !important;
    background-color: rgba(15,25,45,0.95) !important;
    color: #e8f4ff !important;
}

.x-mask-msg, .x-mask-msg-text, div.x-mask-msg-text,
.x-mask-msg-inner, .pve-static-mask, .x-mask.x-border-box {
    background: rgba(15,25,45,0.95) !important;
    background-color: rgba(15,25,45,0.95) !important;
    color: #e8f4ff !important;
    border: 1px solid rgba(0,212,255,0.3) !important;
}


/* Texte en blanc */

.x-grid-item .x-grid-cell,
.x-grid-item .x-grid-cell-inner,
.x-grid-cell, .x-grid-cell-inner {
    color: #e8f4ff !important;
    text-shadow: none !important;
    font-weight: 500 !important;
}

.x-tree-node-text, span.x-tree-node-text {
    color: #ffffff !important;
    text-shadow: none !important;
    font-weight: 400 !important;
}

.x-panel-body h3, .x-panel-body-default h3,
.x-table-layout-cell h3, .x-component h3 {
    color: #e8f4ff !important;
    text-shadow: none !important;
}

.x-panel-body .left-aligned, .x-panel-body-default .left-aligned,
.x-panel-body p, .x-panel-body-default p, .pmx-md p,
.x-autocontainer-innerct p, .x-component.x-component-default,
div[style*="white-space:pre"], .x-autocontainer-innerct > div,
.x-panel-body .x-component, .x-panel-body div, .x-panel-body-default div,
.x-table-layout-ct div, .x-scroller div, .x-docked-noborder-right div,
.x-panel-body span, .x-panel-body-default span, .x-table-layout-cell span,
.centered-flex-column, .x-component.centered-flex-column {
    color: #e8f4ff !important;
}

.x-form-display-field, .x-form-display-field-default {
    color: #e8f4ff !important;
}


/* Étiquettes (tags) : texte noir sur fond clair, blanc sur fond sombre.
 * Dans l'en-tête d'une VM, le texte est dans un span sans classe,
 * d'où les sélecteurs .pve-edit-tag. */

span.proxmox-tag-dark,
span.proxmox-tag-dark[style],
.x-grid-cell span.proxmox-tag-dark[style],
.x-grid-cell-inner span.proxmox-tag-dark[style],
div span.proxmox-tag-dark[style],
.x-panel-body span.proxmox-tag-dark[style],
.x-tree-view span.proxmox-tag-dark[style],
.proxmox-tag-dark.x-component.x-component-default,
.proxmox-tag-dark.x-component.x-component-default span,
.pve-edit-tag.proxmox-tag-dark,
.pve-edit-tag.proxmox-tag-dark span {
    color: #000000 !important;
    text-shadow: none !important;
}

span.proxmox-tag-light,
span.proxmox-tag-light[style],
.x-grid-cell span.proxmox-tag-light[style],
.x-grid-cell-inner span.proxmox-tag-light[style],
div span.proxmox-tag-light[style],
.x-panel-body span.proxmox-tag-light[style],
.x-tree-view span.proxmox-tag-light[style],
.proxmox-tag-light.x-component.x-component-default,
.proxmox-tag-light.x-component.x-component-default span,
.pve-edit-tag.proxmox-tag-light,
.pve-edit-tag.proxmox-tag-light span {
    color: #ffffff !important;
    text-shadow: 0 1px 2px rgba(0,0,0,0.6) !important;
}


/* VM et conteneurs en marche : icône noire avec halo cyan */

.x-grid-item-container .fa-desktop,
.x-grid-item-container .fa-cube,
.x-tree-icon.fa-desktop, .x-tree-icon.fa-cube,
.x-tree-icon-leaf.fa-desktop, .x-tree-icon-leaf.fa-cube,
.x-tree-icon-custom.fa-desktop, .x-tree-icon-custom.fa-cube {
    color: #000000 !important;
    filter: drop-shadow(0 0 6px rgba(0,212,255,0.8))
            drop-shadow(0 0 10px rgba(0,180,255,0.5))
            brightness(1.3) !important;
    animation: none !important;
    background: transparent !important;
    background-color: transparent !important;
}

.x-grid-item:hover .fa-desktop.running,
.x-grid-item:hover .fa-cube.running {
    filter: drop-shadow(0 0 8px rgba(0,255,136,0.9))
            drop-shadow(0 0 12px rgba(0,200,120,0.6))
            brightness(1.4) !important;
}

.x-grid-item-selected .fa-desktop,
.x-grid-item-selected .fa-cube {
    filter: drop-shadow(0 0 10px rgba(0,230,255,0.95))
            drop-shadow(0 0 15px rgba(0,200,255,0.7))
            brightness(1.5) !important;
}


/* VM et conteneurs arrêtés : rouge */

.fa-desktop.stopped, .fa-cube.stopped,
.x-tree-icon.fa-desktop.stopped, .x-tree-icon.fa-cube.stopped,
.x-tree-icon-leaf.fa-desktop.stopped, .x-tree-icon-leaf.fa-cube.stopped,
.x-tree-icon-custom.fa-desktop.stopped, .x-tree-icon-custom.fa-cube.stopped,
.x-grid-item-container .fa-desktop.stopped,
.x-grid-item-container .fa-cube.stopped {
    color: #cc2244 !important;
    filter: drop-shadow(0 0 6px rgba(220,40,80,0.7))
            drop-shadow(0 0 10px rgba(200,30,60,0.4))
            brightness(1.4) !important;
}

.x-grid-item:hover .fa-desktop.stopped,
.x-grid-item:hover .fa-cube.stopped {
    filter: drop-shadow(0 0 8px rgba(255,50,90,0.9))
            drop-shadow(0 0 14px rgba(220,40,80,0.6))
            brightness(1.5) !important;
}


/* Modèles : violet, sans fond */

.fa-file-o,
.fa-file-o::before, .fa-file-o::after,
.x-tree-icon.fa-file-o,
.x-tree-icon-leaf.fa-file-o,
.x-tree-icon-custom.fa-file-o,
div[class*="fa-file-o"],
div[class*="fa-file-o"]::before,
div[class*="fa-file-o"]::after,
.x-grid-item-container .fa-file-o {
    color: #9966aa !important;
    filter: drop-shadow(0 0 4px rgba(150,100,180,0.5)) brightness(1.2) !important;
    animation: none !important;
    background: transparent !important;
    background-color: transparent !important;
    background-image: none !important;
}

.x-grid-item:hover .fa-file-o {
    filter: drop-shadow(0 0 6px rgba(150,100,180,0.7)) brightness(1.3) !important;
}


/* Nœuds : cyan, avec pulsation */

.fa-server,
.x-grid-item-container .fa-server,
.x-tree-icon.fa-server,
.x-tree-icon-parent.fa-server {
    color: #00ffff !important;
    filter: drop-shadow(0 0 14px rgba(0,255,255,1))
            drop-shadow(0 0 22px rgba(0,240,255,0.9))
            drop-shadow(0 0 32px rgba(0,220,255,0.7))
            brightness(1.6) !important;
    animation: none !important;
}

.x-grid-item:hover .fa-server,
.x-tree-node:hover .fa-server {
    filter: drop-shadow(0 0 18px rgba(0,255,255,1))
            drop-shadow(0 0 28px rgba(50,255,255,1))
            drop-shadow(0 0 42px rgba(0,240,255,0.9))
            brightness(1.8) !important;
}

.x-grid-item-selected .fa-server,
.x-tree-node-selected .fa-server {
    filter: drop-shadow(0 0 22px rgba(0,255,255,1))
            drop-shadow(0 0 36px rgba(50,255,255,1))
            drop-shadow(0 0 52px rgba(0,240,255,1))
            brightness(2.0) !important;
    animation: iconServerGlowCyan 2.5s ease-in-out infinite !important;
}

@keyframes iconServerGlowCyan {
    0%, 100% {
        filter: drop-shadow(0 0 22px rgba(0,255,255,1))
                drop-shadow(0 0 36px rgba(50,255,255,0.9))
                brightness(2.0);
    }
    50% {
        filter: drop-shadow(0 0 30px rgba(50,255,255,1))
                drop-shadow(0 0 44px rgba(0,255,255,1))
                brightness(2.3);
    }
}


/* Datacenter : blanc, avec halo */

.x-grid-item-container .fa-building,
.x-tree-icon.fa-building,
.x-tree-icon-parent.fa-building,
.x-tree-icon-parent-expanded.fa-building,
.x-tree-icon-custom.fa-building {
    color: #ffffff !important;
    filter: drop-shadow(0 0 8px rgba(255,255,255,0.9))
            drop-shadow(0 0 12px rgba(255,255,255,0.6))
            drop-shadow(0 0 16px rgba(255,255,255,0.4))
            brightness(1.3) !important;
    animation: none !important;
}

.x-grid-item:hover .fa-building {
    filter: drop-shadow(0 0 10px rgba(255,255,255,1))
            drop-shadow(0 0 16px rgba(255,255,255,0.8))
            drop-shadow(0 0 24px rgba(255,255,255,0.6))
            brightness(1.5) !important;
}

.x-grid-item-selected .fa-building {
    filter: drop-shadow(0 0 14px rgba(255,255,255,1))
            drop-shadow(0 0 22px rgba(255,255,255,0.9))
            drop-shadow(0 0 32px rgba(255,255,255,0.7))
            brightness(1.6) !important;
    animation: iconDatacenterGlowWhite 2s ease-in-out infinite !important;
}

@keyframes iconDatacenterGlowWhite {
    0%, 100% {
        filter: drop-shadow(0 0 14px rgba(255,255,255,0.9))
                drop-shadow(0 0 22px rgba(255,255,255,0.8))
                brightness(1.6);
    }
    50% {
        filter: drop-shadow(0 0 18px rgba(255,255,255,1))
                drop-shadow(0 0 28px rgba(255,255,255,0.9))
                brightness(1.8);
    }
}


/* Icône Ceph (une image) passée en blanc */

.fa-ceph::before,
.fa-ceph:before {
    filter: brightness(0) invert(1) !important;
}


/* Survol et sélection des lignes */

.x-grid-item:hover {
    background: linear-gradient(90deg, rgba(0,200,255,0.25), rgba(0,180,255,0.15)) !important;
    border-left: 4px solid #00d4ff !important;
    box-shadow: inset 0 0 20px rgba(0,212,255,0.3), 0 0 15px rgba(0,200,255,0.4) !important;
    transition: all 0.3s ease !important;
}

.x-grid-item:hover .x-grid-cell { color: #fff !important; }

.x-grid-item-selected {
    /* Halo intérieur léger : plus fort, il rend le texte blanc difficile à lire */
    background: linear-gradient(90deg, rgba(0,212,255,0.4), rgba(0,180,255,0.3)) !important;
    border-left: 6px solid #00d4ff !important;
    box-shadow: inset 0 0 30px rgba(0,220,255,0.22), 0 0 25px rgba(0,212,255,0.8) !important;
}

.x-grid-item-selected .x-grid-cell {
    color: #fff !important;
    font-weight: 700 !important;
}


/* En-têtes des panneaux et des fenêtres */

.x-panel-header, .x-window-header {
    background: linear-gradient(135deg, rgba(20,40,80,0.9), rgba(30,60,100,0.85), rgba(15,45,85,0.88)) !important;
    border-bottom: 2px solid rgba(0,212,255,0.7) !important;
    box-shadow: 0 3px 20px rgba(0,212,255,0.4) !important;
}

.x-panel-header *, .x-window-header * {
    color: #fff !important;
    text-shadow: 0 0 12px rgba(0,230,255,0.9) !important;
}

.x-column-header, .x-grid-header-ct, .x-column-header-inner {
    background: linear-gradient(180deg, rgba(20,40,80,0.9), rgba(15,35,70,0.85)) !important;
    border-bottom: 2px solid rgba(0,212,255,0.6) !important;
}

.x-column-header-text {
    color: #e8f4ff !important;
    text-shadow: 0 0 10px rgba(0,230,255,0.7) !important;
    font-weight: 700 !important;
}


/* Barre du haut */

body > div:first-of-type {
    background: linear-gradient(90deg, rgba(15,25,45,0.96), rgba(20,35,60,0.96), rgba(15,30,50,0.96)) !important;
    border-bottom: 3px solid transparent !important;
    border-image: linear-gradient(90deg, #00d4ff 0%, #0099ff 50%, #00d4ff 100%) 1 !important;
    box-shadow: 0 4px 25px rgba(0,212,255,0.4) !important;
}


/* Menus contextuels et actions groupées */

.x-menu {
    background: rgba(15,25,45,0.96) !important;
    backdrop-filter: blur(15px) !important;
    border: 2px solid rgba(0,212,255,0.5) !important;
    box-shadow: 0 12px 40px rgba(0,0,0,0.7), 0 0 30px rgba(0,212,255,0.3) !important;
    border-radius: 10px !important;
}

.x-menu-item {
    border-radius: 6px !important;
    margin: 2px 4px !important;
    transition: all 0.3s ease !important;
}

.x-menu-item .x-menu-item-text {
    color: #e8f4ff !important;
    text-shadow: 0 0 8px rgba(0,212,255,0.5) !important;
    font-weight: 600 !important;
}

.x-menu-item-active,
.x-menu-item.x-menu-item-active,
.x-menu-item:hover {
    background: linear-gradient(90deg, rgba(0,200,255,0.25), rgba(0,180,255,0.15)) !important;
    border-radius: 6px !important;
}

.x-menu-item:hover .x-menu-item-text,
.x-menu-item-active .x-menu-item-text {
    color: #fff !important;
    text-shadow: 0 0 12px rgba(0,230,255,0.9) !important;
    font-weight: 700 !important;
}

.x-menu-item .x-menu-item-icon {
    color: #e8f4ff !important;
    filter: drop-shadow(0 0 6px rgba(0,212,255,0.6)) !important;
}

.x-menu-item .fa-play,
.x-menu-item .x-menu-item-icon.fa-play {
    color: #00cc66 !important;
    filter: drop-shadow(0 0 6px rgba(0,200,100,0.6)) !important;
}

.x-menu-item .fa-stop,
.x-menu-item .x-menu-item-icon.fa-stop {
    color: #cc3344 !important;
    filter: drop-shadow(0 0 6px rgba(200,50,70,0.6)) !important;
}

.x-menu-item .fa-pause,
.x-menu-item .x-menu-item-icon.fa-pause {
    color: #cc8833 !important;
    filter: drop-shadow(0 0 6px rgba(200,130,50,0.6)) !important;
}

.x-menu-item .fa-power-off,
.x-menu-item .x-menu-item-icon.fa-power-off {
    color: #cc3344 !important;
    filter: drop-shadow(0 0 6px rgba(200,50,70,0.6)) !important;
}


/* Boutons de la barre du haut */

.x-toolbar .x-btn, .x-docked-top .x-btn {
    background: linear-gradient(135deg, rgba(15,25,50,0.9), rgba(20,35,65,0.85)) !important;
    border: 1px solid rgba(0,212,255,0.3) !important;
    border-radius: 6px !important;
    transition: all 0.3s ease !important;
}

.x-toolbar .x-btn:hover, .x-docked-top .x-btn:hover {
    background: linear-gradient(135deg, rgba(20,35,65,0.95), rgba(25,45,80,0.9)) !important;
    border-color: rgba(0,212,255,0.6) !important;
    box-shadow: 0 0 12px rgba(0,212,255,0.4) !important;
}

.x-toolbar .x-btn .x-btn-inner, .x-docked-top .x-btn .x-btn-inner {
    color: #e8f4ff !important;
    font-weight: 600 !important;
}

.x-toolbar .x-btn:hover .x-btn-inner {
    color: #fff !important;
    text-shadow: 0 0 10px rgba(0,230,255,0.8) !important;
}

.x-btn-success {
    background: rgba(0,200,120,0.5) !important;
    border: 2px solid #00ff88 !important;
}
.x-btn-success * { color: #fff !important; font-weight: bold !important; }

.x-btn-danger {
    background: rgba(220,50,80,0.5) !important;
    border: 2px solid #ff4466 !important;
}
.x-btn-danger * { color: #fff !important; font-weight: bold !important; }

.x-btn-split-right {
    border-left: 1px solid rgba(0,212,255,0.3) !important;
}


/* Arborescence de gauche */

.x-treelist, .x-treelist-container, .x-treelist-row-over,
.x-treelist-item-wrap, .pve-nav-tree, .x-treelist-navigation {
    background: linear-gradient(180deg, rgba(15,25,45,0.95), rgba(20,30,50,0.92)) !important;
}

.x-treelist-item, .x-treelist-row {
    background: transparent !important;
    border-left: 3px solid transparent !important;
    transition: all 0.3s ease !important;
    margin: 2px 0 !important;
}

.x-treelist-item-over, .x-treelist-row-over,
.x-treelist-item:hover, .x-treelist-row:hover {
    background: linear-gradient(90deg, rgba(0,200,255,0.25), rgba(0,180,255,0.15)) !important;
    border-left: 4px solid #00d4ff !important;
}

.x-treelist-item-selected, .x-treelist-row-selected {
    background: linear-gradient(90deg, rgba(0,212,255,0.35), rgba(0,190,255,0.25)) !important;
    border-left: 5px solid #00d4ff !important;
    box-shadow: inset 0 0 30px rgba(0,220,255,0.5), 0 0 15px rgba(0,212,255,0.6) !important;
}

.x-treelist-item-text {
    color: #e8f4ff !important;
    text-shadow: 0 0 10px rgba(0,212,255,0.5) !important;
    font-weight: 600 !important;
}

.x-treelist-item-selected .x-treelist-item-text {
    color: #fff !important;
    text-shadow: 0 0 15px rgba(0,230,255,0.9) !important;
    font-weight: 700 !important;
}

.x-treelist-item-icon, .x-treelist-item-icon.fa {
    color: #fff !important;
    filter: drop-shadow(0 0 8px rgba(255,255,255,0.6)) !important;
}

.x-treelist-item-selected .x-treelist-item-icon {
    filter: drop-shadow(0 0 12px rgba(255,255,255,0.9)) !important;
}

.x-treelist::before, .x-treelist-container::before {
    content: "";
    position: absolute; top: 0; left: 0; right: 0; height: 3px;
    background: linear-gradient(90deg, #00d4ff 0%, #0099ff 50%, #00d4ff 100%) !important;
    background-size: 200% 100% !important;
    animation: elecBorder 3s linear infinite !important;
    z-index: 10;
}

@keyframes elecBorder {
    0%   { background-position: 0% 50%; }
    100% { background-position: 200% 50%; }
}

.x-panel.x-box-layout-ct, .x-box-inner {
    background: linear-gradient(180deg, rgba(15,25,45,0.95), rgba(20,30,50,0.92)) !important;
}


/* Onglets */

.x-tab.x-tab-active,
.x-tab.x-tab-default.x-tab-active {
    background: linear-gradient(180deg, rgba(0,212,255,0.3), rgba(0,180,255,0.15)) !important;
    border-bottom: 2px solid #00d4ff !important;
}

.x-tab.x-tab-active .x-tab-inner,
.x-tab.x-tab-default.x-tab-active .x-tab-inner {
    color: #ffffff !important;
    text-shadow: 0 0 10px rgba(0,230,255,0.8) !important;
    font-weight: 700 !important;
}

.x-tab .x-tab-inner,
.x-tab.x-tab-default .x-tab-inner {
    color: #70a8c8 !important;
    text-shadow: none !important;
    font-weight: 500 !important;
}

.x-tab:hover .x-tab-inner {
    color: #b0d8f0 !important;
}


/* Champs de formulaire */

.x-btn-inner {
    color: #e8f4ff !important;
    font-weight: 600 !important;
}

input, input[type="text"], input[type="password"], select, textarea {
    background: rgba(20,30,50,0.8) !important;
    border: 1px solid rgba(0,212,255,0.4) !important;
    color: #e8f4ff !important;
}

input:focus, select:focus, textarea:focus {
    border-color: #00d4ff !important;
    box-shadow: 0 0 10px rgba(0,212,255,0.5) !important;
}

.x-form-item-label, .x-form-item-label-text, .x-panel-body label {
    color: #e8f4ff !important;
}

.x-btn-default-toolbar-small {
    background: linear-gradient(135deg, rgba(15,25,45,0.9), rgba(20,35,60,0.85)) !important;
    border: 1px solid rgba(0,212,255,0.4) !important;
}

.x-btn-default-toolbar-small:hover {
    background: linear-gradient(135deg, rgba(20,35,60,0.95), rgba(25,45,75,0.9)) !important;
    border-color: rgba(0,212,255,0.6) !important;
}

.x-boundlist-default {
    background: rgba(15,25,45,0.95) !important;
    border: 1px solid rgba(0,212,255,0.5) !important;
}

.x-boundlist-item { color: #e8f4ff !important; }

.x-boundlist-item-over {
    background: linear-gradient(90deg, rgba(0,200,255,0.25), rgba(0,180,255,0.15)) !important;
}

.x-boundlist-selected {
    background: linear-gradient(90deg, rgba(0,212,255,0.4), rgba(0,180,255,0.3)) !important;
}


/* Barres de défilement */

::-webkit-scrollbar { width: 12px; background: #0a0e1a; }

::-webkit-scrollbar-thumb {
    background: linear-gradient(180deg, #00d4ff, #0099ff, #00d4ff) !important;
    border-radius: 8px !important;
}

::-webkit-scrollbar-thumb:hover {
    box-shadow: 0 0 20px rgba(0,230,255,1) !important;
}


/* Barres de progression (CPU, mémoire, disque) */

.x-progress, .x-progress-default {
    background: rgba(15,25,45,0.8) !important;
    border: 1px solid rgba(0,212,255,0.3) !important;
    border-radius: 4px !important;
}

.x-progress-bar, .x-progress-bar-default {
    background: linear-gradient(90deg,
        rgba(0,212,255,0.8) 0%, rgba(0,180,255,0.9) 40%,
        rgba(0,255,136,0.8) 60%, rgba(255,200,0,0.9) 80%,
        rgba(255,68,102,0.9) 95%) !important;
    border-radius: 3px !important;
}

.x-progress-text, .x-progress-text-back {
    color: #fff !important;
    text-shadow: 0 1px 3px rgba(0,0,0,0.8) !important;
    font-weight: 700 !important;
}


/* Console */

.pve-xtermjs,
.x-panel-body iframe[src*="xtermjs"],
.x-panel-body iframe[src*="consoletype"] {
    border: 2px solid rgba(0,212,255,0.3) !important;
    border-radius: 6px !important;
    box-shadow: 0 0 15px rgba(0,212,255,0.2) !important;
}

.x-autocontainer-innerCt iframe {
    border: 2px solid rgba(0,212,255,0.25) !important;
    border-radius: 4px !important;
}


/* Fenêtres */

.x-window {
    background: rgba(12,20,40,0.97) !important;
    border: 2px solid rgba(0,212,255,0.5) !important;
    border-radius: 10px !important;
    box-shadow: 0 0 30px rgba(0,212,255,0.3), 0 20px 60px rgba(0,0,0,0.6) !important;
}

.x-window-header { border-radius: 8px 8px 0 0 !important; }

.x-window-header-title .x-title-text {
    color: #fff !important;
    text-shadow: 0 0 12px rgba(0,230,255,0.8) !important;
    font-weight: 700 !important;
}

.x-window-header .x-tool-close { color: #ff6688 !important; }

.x-window-header .x-tool-close:hover {
    color: #ff4466 !important;
    filter: drop-shadow(0 0 8px rgba(255,68,102,0.8)) !important;
}

.x-window-body { background: rgba(15,25,45,0.95) !important; }

.x-window .x-toolbar-footer .x-btn {
    background: linear-gradient(135deg, rgba(15,30,55,0.9), rgba(20,40,70,0.85)) !important;
    border: 1px solid rgba(0,212,255,0.4) !important;
    border-radius: 6px !important;
}

.x-window .x-toolbar-footer .x-btn:hover {
    border-color: rgba(0,212,255,0.7) !important;
    box-shadow: 0 0 10px rgba(0,212,255,0.4) !important;
}

.x-mask { background: rgba(5,10,20,0.7) !important; }

.x-message-box {
    background: rgba(12,20,40,0.97) !important;
    border: 2px solid rgba(0,212,255,0.5) !important;
    border-radius: 10px !important;
}


/* Infobulles */

.x-tip, .x-tip-default, .x-tooltip {
    background: rgba(12,20,40,0.96) !important;
    border: 1px solid rgba(0,212,255,0.5) !important;
    border-radius: 6px !important;
    box-shadow: 0 0 15px rgba(0,212,255,0.3), 0 4px 12px rgba(0,0,0,0.5) !important;
}

.x-tip-body, .x-tip-body-default, .x-tooltip-body {
    color: #e8f4ff !important;
    font-weight: 500 !important;
}

.x-tip-header, .x-tip-header-title {
    color: #fff !important;
    font-weight: 700 !important;
}


/* Graphiques */

.proxmox-rrd-chart, .pve-rrds,
img[src*="rrd"], img[src*="graph"],
.x-panel-body img[src*="api2"] {
    filter: invert(1) hue-rotate(180deg) saturate(1.5) brightness(0.85) contrast(1.1) !important;
    border: 1px solid rgba(0,212,255,0.2) !important;
    border-radius: 4px !important;
}


/* Logo Proxmox remplacé par du texte néon */

a[id^="proxmoxlogo" i] img,
img[src*="proxmox_logo"], img[alt*="Proxmox"] {
    display: none !important;
}

a[id^="proxmoxlogo" i] {
    font-size: 0 !important;
    display: inline-flex !important;
    align-items: center !important;
}

a[id^="proxmoxlogo" i]::before {
    content: "PROXMOX" !important;
    font-family: 'Orbitron', 'Consolas', 'Lucida Console', monospace !important;
    font-size: 22px !important;
    font-weight: 900 !important;
    letter-spacing: 3px !important;
    color: #00e5ff !important;
    animation: logoPulse 2.5s ease-in-out infinite !important;
}

@keyframes logoPulse {
    0%, 100% {
        text-shadow:
            0 0 8px rgba(0,230,255,0.7),
            0 0 16px rgba(0,212,255,0.4),
            0 0 30px rgba(0,180,255,0.2);
    }
    50% {
        text-shadow:
            0 0 14px rgba(0,230,255,1),
            0 0 28px rgba(0,212,255,0.8),
            0 0 50px rgba(0,180,255,0.5),
            0 0 80px rgba(0,150,255,0.3);
    }
}


/* Badge de la barre du haut, séparé du logo par un trait lumineux */

/* ExtJS fixe la largeur de #versioninfo d'après le texte d'origine :
 * sans ces lignes, un badge plus long serait coupé. */
#versioninfo,
#versioninfo-innerCt {
    width: auto !important;
    max-width: none !important;
    overflow: visible !important;
}

#versioninfo-innerCt {
    font-size: 0 !important;
    display: inline-block !important;
    margin-left: 20px !important;
    padding-left: 20px !important;
    border-left: 2px solid transparent !important;
    border-image: linear-gradient(180deg, transparent, rgba(0,212,255,0.6), transparent) 1 !important;
}

#versioninfo-innerCt::before {
    content: "@@BADGE@@" !important;
    font-family: 'Orbitron', 'Arial Black', sans-serif !important;
    font-size: 16px !important;
    font-weight: 900 !important;
    letter-spacing: 2px !important;
    text-transform: uppercase !important;
    white-space: nowrap !important;
    display: inline-block !important;
    background: linear-gradient(90deg, #00e5ff 0%, #00ffaa 50%, #00e5ff 100%) !important;
    background-size: 200% 100% !important;
    -webkit-background-clip: text !important;
    -webkit-text-fill-color: transparent !important;
    background-clip: text !important;
    filter: drop-shadow(0 0 15px rgba(0,230,255,0.9))
            drop-shadow(0 0 25px rgba(0,230,255,0.6)) !important;
    animation: textGrad 4s linear infinite !important;
    padding: 6px 14px !important;
    border: 2px solid rgba(0,230,255,0.4) !important;
    border-radius: 8px !important;
    background-color: rgba(0,230,255,0.08) !important;
}

@keyframes textGrad {
    0%   { background-position: 0% 50%; }
    50%  { background-position: 100% 50%; }
    100% { background-position: 200% 50%; }
}


/* Tâches en erreur : rouge au lieu de l'orange de Proxmox */

.proxmox-invalid-row {
    background: linear-gradient(90deg, rgba(255,60,80,0.15), rgba(255,60,80,0.05)) !important;
    border-left: 3px solid rgba(255,80,100,0.6) !important;
}

.proxmox-invalid-row td,
.proxmox-invalid-row .x-grid-cell,
.proxmox-invalid-row .x-grid-cell-inner,
.proxmox-invalid-row div {
    color: #ff6b7f !important;
    text-shadow: 0 0 6px rgba(255,80,100,0.3) !important;
    font-weight: 600 !important;
}


/* Onglets du bas (Tâches, Journal du cluster) */

div[id^="pveStatusPanel"] .x-tab {
    background: transparent !important;
    border: 1px solid rgba(0,212,255,0.2) !important;
    border-radius: 4px 4px 0 0 !important;
}

div[id^="pveStatusPanel"] .x-tab .x-tab-inner {
    /* Opacité 0.8 au moins, sinon l'onglet inactif se lit mal */
    color: rgba(0,212,255,0.8) !important;
    text-shadow: none !important;
    font-weight: 500 !important;
}

div[id^="pveStatusPanel"] .x-tab:hover {
    background: rgba(0,212,255,0.1) !important;
    border-color: rgba(0,212,255,0.4) !important;
}

div[id^="pveStatusPanel"] .x-tab:hover .x-tab-inner {
    color: rgba(0,212,255,0.95) !important;
}

div[id^="pveStatusPanel"] .x-tab.x-tab-active {
    background: linear-gradient(180deg, rgba(0,212,255,0.25), rgba(0,180,255,0.1)) !important;
    border-color: rgba(0,212,255,0.5) !important;
    border-bottom: 2px solid #00d4ff !important;
}

div[id^="pveStatusPanel"] .x-tab.x-tab-active .x-tab-inner {
    color: #00d4ff !important;
    text-shadow: 0 0 8px rgba(0,212,255,0.5) !important;
    font-weight: 700 !important;
}


/* Signature discrète à droite des onglets du bas.
 * Licence CC BY-NC-SA : à garder si vous redistribuez le thème. */

div[id^="pveStatusPanel-"][class~="x-panel"] .x-tab-bar {
    position: relative !important;
    overflow: visible !important;
}

div[id^="pveStatusPanel-"][class~="x-panel"] .x-tab-bar::after {
    content: "\00A9  2025-2026 D. SCONTRINO" !important;
    position: absolute !important;
    right: 12px !important;
    top: 50% !important;
    transform: translateY(-50%) !important;
    font-size: 10px !important;
    font-weight: 400 !important;
    letter-spacing: 0.5px !important;
    color: rgba(0,212,255,0.25) !important;
    text-shadow: none !important;
    pointer-events: none !important;
    white-space: nowrap !important;
    z-index: 10 !important;
}


/* Fenêtre du message d'accueil */

.tpc-message .x-window-body,
.tpc-message .x-autocontainer-innerCt {
    background: rgba(12,20,40,0.97) !important;
}

.tpc-message-contenu,
.tpc-message-contenu p,
.tpc-message-contenu li {
    color: #e8f4ff !important;
    font-size: 14px !important;
    line-height: 1.6 !important;
}

.tpc-message-contenu h1, .tpc-message-contenu h2, .tpc-message-contenu h3 {
    color: #00e5ff !important;
    text-shadow: 0 0 10px rgba(0,230,255,0.6) !important;
    margin: 0.4em 0 0.5em 0 !important;
}

.tpc-message-contenu strong, .tpc-message-contenu b { color: #ffffff !important; }
.tpc-message-contenu a { color: #00e5ff !important; }
.tpc-message-contenu ul, .tpc-message-contenu ol { padding-left: 1.4em !important; }

/* Le thème sombre de Proxmox inverse les cellules à icône (processeur, mémoire,
 * disques…) et met leur texte en noir pour compenser : on lui laisse ce réglage. */

.pve-itype-icon-cpu .x-grid-cell-inner,
.pve-itype-icon-cdrom .x-grid-cell-inner,
.pve-itype-icon-memory .x-grid-cell-inner,
.pve-itype-icon-pci .x-grid-cell-inner,
.pve-itype-icon-serial .x-grid-cell-inner,
.pve-itype-icon-die .x-grid-cell-inner,
.pmx-itype-icon-processor .x-grid-cell-inner,
.pmx-itype-icon-memory .x-grid-cell-inner,
.pve-itype-icon-storage .x-grid-cell-inner,
.x-tree-node-harddisk .x-grid-cell-inner,
.x-grid-tree-node-expanded .x-tree-node-harddisk .x-grid-cell-inner {
    color: #0b0b0b !important;
    text-shadow: none !important;
}


/* Animations coupées quand le système demande « réduire les animations ».
 * Chaque sélecteur animé est repris : « * » seul ne suffirait pas. */

@media (prefers-reduced-motion: reduce) {
    *, *::before, *::after,
    body::before,
    .x-grid-item-container .fa-desktop, .x-grid-item-container .fa-cube,
    .x-tree-icon.fa-desktop, .x-tree-icon.fa-cube,
    .x-tree-icon-leaf.fa-desktop, .x-tree-icon-leaf.fa-cube,
    .x-tree-icon-custom.fa-desktop, .x-tree-icon-custom.fa-cube,
    .fa-file-o, .fa-file-o::before, .fa-file-o::after,
    .x-tree-icon.fa-file-o, .x-tree-icon-leaf.fa-file-o,
    .x-tree-icon-custom.fa-file-o,
    div[class*="fa-file-o"], div[class*="fa-file-o"]::before,
    div[class*="fa-file-o"]::after, .x-grid-item-container .fa-file-o,
    .fa-server, .x-grid-item-container .fa-server,
    .x-tree-icon.fa-server, .x-tree-icon-parent.fa-server,
    .x-grid-item-selected .fa-server, .x-tree-node-selected .fa-server,
    .x-grid-item-container .fa-building, .x-tree-icon.fa-building,
    .x-tree-icon-parent.fa-building, .x-tree-icon-parent-expanded.fa-building,
    .x-tree-icon-custom.fa-building, .x-grid-item-selected .fa-building,
    .x-treelist::before, .x-treelist-container::before,
    a[id^="proxmoxlogo" i]::before,
    #versioninfo-innerCt::before {
        animation: none !important;
        transition: none !important;
    }
}
FIN_CSS
}

script_message() {
cat <<'FIN_JS'
/* Message d'accueil du thème néon pour Proxmox VE.
 * Fichier créé par install_theme_proxmox.sh : relancer le script pour le modifier.
 * Tout est dans des try/catch : une erreur ici ne bloque pas l'interface. */
(function () {
    // Pas de 'use strict' : le callParent() d'ExtJS ne le supporte pas.
    var REGLAGES = {
        cle: @@CLE@@,
        titre: @@TITRE@@,
        message: @@MESSAGE@@
    };
    var signaler = function (quoi, e) {
        if (window.console && console.error) { console.error('theme-proxmox-cyberpunk (' + quoi + ') :', e); }
    };

    /* Proxmox laisse Ext.Component.layoutSuspendCount à 1 : une fenêtre ouverte après
     * coup n'est pas mise en page, et le bouton « J'ai compris » se retrouve hors de
     * la fenêtre. On remet le compteur à 0 le temps de la mise en page. */
    var reposer = function (w) {
        var n = Ext.Component.layoutSuspendCount;
        Ext.Component.layoutSuspendCount = 0;
        try { w.updateLayout(); w.center(); } finally { Ext.Component.layoutSuspendCount = n; }
    };

    // Affiché après la connexion, une fois par session du navigateur,
    // et de nouveau si le message change
    if (REGLAGES.message) {
        Ext.onReady(function () {
            var essais = 0, stable = 0;
            var minuteur = setInterval(function () {
                essais += 1;
                if (essais > 7200) { clearInterval(minuteur); return; }
                // On attend 2 s d'interface stable (connecté, page affichée, aucune
                // fenêtre ouverte), sinon le message s'ouvre derrière celle de connexion
                try {
                    var connecte = typeof Proxmox !== 'undefined' && !!Proxmox.UserName;
                    var vue = Ext.ComponentQuery.query('viewport')[0];
                    var occupe = Ext.ComponentQuery.query('window[modal=true]').some(function (w) {
                        return w.isVisible();
                    });
                    if (!connecte || !vue || !vue.rendered || occupe) { stable = 0; return; }
                } catch (e) { stable = 0; return; }
                stable += 1;
                if (stable < 2) { return; }
                clearInterval(minuteur);
                try {
                    try {
                        if (window.sessionStorage.getItem('theme-proxmox-message') === REGLAGES.cle) { return; }
                        window.sessionStorage.setItem('theme-proxmox-message', REGLAGES.cle);
                    } catch (e) { /* stockage indisponible : on affiche quand même */ }
                    var taille = Ext.getBody().getViewSize();
                    Ext.create('Ext.window.Window', {
                        title: REGLAGES.titre,
                        cls: 'tpc-message',
                        modal: true,
                        constrain: true,
                        width: Math.min(760, Math.round(taille.width * 0.92)),
                        maxHeight: Math.round(taille.height * 0.85),
                        scrollable: true,
                        bodyPadding: 22,
                        html: '<div class="tpc-message-contenu">' + REGLAGES.message + '</div>',
                        buttons: [{
                            text: "J'ai compris",
                            handler: function (b) { b.up('window').close(); }
                        }],
                        listeners: {
                            show: function (w) {
                                try { reposer(w); } catch (e) { signaler('message', e); }
                                Ext.defer(function () {
                                    try { reposer(w); } catch (e) { signaler('message', e); }
                                }, 300);
                            }
                        }
                    }).show();
                } catch (e) { signaler('message', e); }
            }, 1000);
        });
    }
})();
FIN_JS
}

# Police Orbitron d'origine (https://github.com/theleagueof/orbitron : Orbitron-Bold = 700,
# Orbitron-Black = 900), encodée par « base64 -w76 ». Contrôle : police 700 | base64 -d | sha256sum
# donne a24fe803…2a952 pour la 700 et 27cd3130…9de61 pour la 900.
police() {   # $1 = 700 ou 900
    if [ "$1" = 700 ]; then
        tr -d '\n' <<'FIN_B64'
AAEAAAAQAQAABAAAR0RFRgRJBGkAAAJMAAAAdkdQT1P4ncahAAAPCAAACbhHU1VCuPy46gAAAWAA
AAAoT1MvMmFczBEAAAHsAAAAYFNUQVR5k2tJAAABiAAAACpjbWFwyaNyCQAACSQAAAKmZ2FzcAAA
ABAAAAEUAAAACGdseWbdpKZ9AAAYwAAALGxoZWFkCpikxwAAAbQAAAA2aGhlYQhTAzMAAAE8AAAA
JGhtdHjvqh86AAALzAAAAzxsb2Nha3dgjAAAAsQAAAGibWF4cADcAJgAAAEcAAAAIG5hbWUxPVJC
AAAEaAAAAkpwb3N07p4E4gAABrQAAAJtcHJlcGgGjIUAAAEMAAAAB7gB/4WwBI0AAAEAAf//AA8A
AQAAANAAUwAFAEMABAABAAAAAAAAAAAAAAAAAAIAAQABAAAD8/8NAAAFX/9F/fgFGAABAAAAAAAA
AAAAAAAAAAAAzgABAAAACgAmACYAAkRGTFQAEmxhdG4ADgAAAAAABAAAAAD//wAAAAAAAQABAAgA
AQAAABQAAQAAABwAAndnaHQBAAAAAAIAAQAAAAABBAK8AAAAAAABAAAAAgBCRrNM/l8PPPUAAwPo
AAAAAMoDDTEAAAAA3R9Tk/9F/wYFGAPYAAEABgACAAAAAAAAAAQChQK8AAUAAAKKAlgAAABLAooC
WAAAAV4AMgFcAAAAAAAAAAAAAAAAgAAAZxAAAEIAAAAAAAAAAE5PTkUAoAAg4AwD8/8NAAAD8wDz
AAAAAQAAAAACRALQAAAAIAACAAEAAAAMAAAAAAAAAAIAEQABAAcAAQAKAAsAAQANABEAAQAVABkA
AQAeACUAAQAoACgAAQAqACsAAQAtADEAAQA1AEAAAQBDAEQAAQBGAEoAAQBPAFMAAQBYAF8AAQBk
AGUAAQBoAGwAAQBwAHQAAQCxALkAAwAAAAAAFgBBAE0AWQBlAHEAfQCJALgBAgElATABXQFzAX8B
iwGXAaMBtwHyAgkCFQIhAi0COQJFAmcChAKTAq4CxALQAwcDEwMfAysDNwNDA3kDpwPmBB0EagR2
BIkErQS5BMUE0QTdBPIFEAUxBUgFVAVgBXYFggWrBbcFwwXPBdsF5wXzBjMGYgaGBpEGwQb0BwAH
DAcYByQHPweAB6EHtAfBB8wH1wfiB+0ICwglCD0IZwiGCJIIygjWCOII7gj6CQYJUAmACbEJyQoX
CiMKZAqACqQKsAq8CsgK1AroCwULIgtOC1oLZgt8C4gLvwvQDA4MWwx3DLEM8A0JDWQNqA20DcQN
1w3uDgUOGA4rDl4OkQ6mDsMO8w8EDxUPNw9ZD4MPrQ++D88P3A/pD/YQAxAgEDsQTBBdEHAQfRB9
EH0QsxDkEUYRdRGJEZYRtBHOEeIR9BIIEicSlxLrEzkTahOfE6wTvxPLE9kT5xP5FAsUORRSFF8U
aBRxFHoUghSLFJQUsBS4FMEUzhTXFOMU9xUsFVoVkxWvFc8V7xYDFh0WNgAAAAAACgB+AAMAAQQJ
AAAA9gDWAAMAAQQJAAEAEADGAAMAAQQJAAIACAC+AAMAAQQJAAMAMACOAAMAAQQJAAQAGgB0AAMA
AQQJAAUAGgBaAAMAAQQJAAYAGgBAAAMAAQQJAA4ANAAMAAMAAQQJAQAADAAAAAMAAQQJAQQACAC+
AFcAZQBpAGcAaAB0AGgAdAB0AHAAOgAvAC8AcwBjAHIAaQBwAHQAcwAuAHMAaQBsAC4AbwByAGcA
LwBPAEYATABPAHIAYgBpAHQAcgBvAG4ALQBCAG8AbABkAFYAZQByAHMAaQBvAG4AIAAyAC4AMAAw
ADEATwByAGIAaQB0AHIAbwBuACAAQgBvAGwAZAAyAC4AMAAwADEAOwBOAE8ATgBFADsATwByAGIA
aQB0AHIAbwBuAC0AQgBvAGwAZABCAG8AbABkAE8AcgBiAGkAdAByAG8AbgBDAG8AcAB5AHIAaQBn
AGgAdAAgADIAMAAxADgAIABUAGgAZQAgAE8AcgBiAGkAdAByAG8AbgAgAFAAcgBvAGoAZQBjAHQA
IABBAHUAdABoAG8AcgBzACAAKABoAHQAdABwAHMAOgAvAC8AZwBpAHQAaAB1AGIALgBjAG8AbQAv
AHQAaABlAGwAZQBhAGcAdQBlAG8AZgAvAG8AcgBiAGkAdAByAG8AbgApACwAIAB3AGkAdABoACAA
UgBlAHMAZQByAHYAZQBkACAARgBvAG4AdAAgAE4AYQBtAGUAOgAgACIATwByAGIAaQB0AHIAbwBu
ACIALgAAAAIAAAAAAAD/nAAyAAAAAAAAAAAAAAAAAAAAAAAAAAAA0AAAACQAyQDHAGIArQBjAK4A
kAAlACYAZAAnACgAZQDIAMoAywApACoAKwAsAMwAzQDOAM8ALQAuAC8AMAAxAGYAMgDQANEAZwDT
AK8AsAAzADQANQA2AOQANwA4ANQA1QBoANYAOQA6ADsAPADrALsAPQDmAEQAaQBrAGwAagBuAG0A
oABFAEYAbwBHAEgAcAByAHMAcQBJAEoASwBMANcAdAB2AHcAdQBNAE4ATwBQAFEAeABSAHkAewB8
AHoAfQCxAFMAVABVAFYA5QCJAFcAWAB+AIAAgQB/AFkAWgBbAFwA7AC6AF0A5wATABQAFQAWABcA
GAAZABoAGwAcABEADwAdAB4AqwAEAKMAIgCiAIcADQAGABIAPwALAAwAXgBgAD4AQAAQALIAswBC
ALQAtQC2ALcABQAKAAMBAgEDAIQABwCFAA4A7wDwALgAIAAhAB8AYQAIACMACQCIAIMAXwEEAQUB
BgEHAQgBCQEKAQsBDACOANwAQwCNANgA4QDbAN0A2QDaAN4A4AENAQ4BDwEQAREBEgETARQBFQEW
B3VuaTAwQTAERXVybwd1bmkwMzA4B3VuaTAzMDcJZ3JhdmVjb21iCWFjdXRlY29tYgd1bmkwMzAy
B3VuaTAzMEMHdW5pMDMwQQl0aWxkZWNvbWIHdW5pMDMyNwd1bmlFMDAyB3VuaUUwMDMHdW5pRTAw
NQd1bmlFMDA2B3VuaUUwMDcHdW5pRTAwOAd1bmlFMDA5B3VuaUUwMEEHdW5pRTAwQgd1bmlFMDBD
AAAAAAAAAgAAAAMAAAAUAAMAAQAAABQABAKSAAAATgBAAAUADgAvADkAXQB+AKMAqACwALQAtgC4
AM8A1wDdAO8A9wD9AP8BMQFTAWEBeAF+AscC3AMDAwgDCgMMAycgFCAZIB0gIiAmIKwiEuAD4Az/
/wAAACAAMAA6AF8AoACoAK8AtAC2ALgAvwDRANkA3wDxAPkA/wExAVIBYAF4AX0CxgLYAwADBwMK
AwwDJyATIBggHCAiICYgrCIS4ALgBf//AAAARQAAAAAAAAASAAAACf/4AAwAAAAAAAAAAAAAAAD/
c/8eAAAAAP6/AAD9+AAAAAAAAP2t/ar9kuCB4IHge+Bm4F3f896SIMQgwwABAE4AAABqALAA7gAA
APIAAAAAAAAA7gEOARoBIgFCAU4AAAAAAVIBVAAAAVQAAAFUAVwBYgAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAJ0AhACbAIoAoQCrAK0AnACNAI4AiQCjAIAAkwB/AIsAgQCCAKkApwCoAIYArAAB
AAkACgAMAA0AEgATABQAFQAaABsAHAAdAB4AIAAnACgAKQAqACwALQAyADMANAA1ADgAkQCMAJIA
lgC8ADoAQgBDAEUARgBLAEwATQBOAFQAVQBWAFcAWABaAGEAYgBjAGQAZwBoAG0AbgBvAHAAcwCP
ALAAkACqAJ4AhQCgAKIAwwCvAIcABQACAAMABwAEAAYACAALABEADgAPABAAGQAWABcAGAAfACQA
IQAiACUAIwClADEALgAvADAANgBmAD4AOwA8AEAAPQA/AEEARABKAEcASABJAFMAUABRAFIAWQBe
AFsAXABfAF0ApgBsAGkAagBrAHEAJgBgACsAZQA5AHQAwAC7AMEAxQDCALMAtAC1ALgAsgCxAAAB
9AAUA0QAOgNEADoDRAA6A0QAOgNEADoDRAA6A0QAOgVfADYDQAA7AzYAOAM2ADgDQgA6Av4AOgL+
ADoC/gA6Av4AOgL+ADoC0wA6Az4AOANTADkA1gAqANYAJADW/9oA1v/GANYABAMMAAQDHQA5AwsA
OQOgADgDQAA4A0AAOAM8ADYDPAA2AzwANgM8ADYDPAA2AzwANgVeADUDFwA4A3QANgM5ADgDOgA1
AzoANQL3ABQDPAA2AzwANgM8ADYDPAA2AzwANgPrACMEmwAjAywALgMmAAQDJgAEAyYABAM1ADMD
NQAzArYANAK2ADQCtgA0ArYANAK2ADQCtgA0ArYANASaADQCmwA2ArcAMwK3ADMCmwAXArQAMwK0
ADMCtAAzArQAMwK0ADMBrgA1AqsAKQKcADYA3gA0ANYAKgDWACIA1v/YANb/xADWAAIA7/9FAoYA
NgFGADQD0gA2ArgANgK4ADYCtAAzArQAMwK0ADMCtAAzArQAMwK0ADMEmQA0ApgANgKYABQCCgA0
Aq4AMAKuADADQQA5AbYANQK3ADUCtwA1ArcANQK3ADUCtwA1AxYAFQQjACMCtAAuAq0AKgKtACoC
rQAqAroANgK6ADYDQgA5AYcAAQM+ADkDOgA1AtoABgM+ADkDNAA5ApQAAwNCADkDPAA1AOMANgDj
ADYA7QA2APMAMwI+ADYA3AA6ANIANQKmAB8CowATAXMAdwH8ABkDHQAgAgkABgIIAAUBIQA0ASMA
OAEhABcBIQAzARMANgEUADMCBQA7AsQANgM2ADYDPAA2AbIALgGyADYA2gAiANgANgGFACsA8wA7
ATIAAAEyAAADHwAjAnwAIQMUACIC3gAnAcAAEQIFADsCIgA1AgQACgJ+ADsB2wA7AdkABQGUABgD
xgAwAzQANgOqADUDQQA4AbcALQDWADYAAP9ZAAD/vgAA/5cAAP+3AAD/bQAA/3IAAP+gAAD/SgAA
AVMCGABkARUASQEdADsA1QAmAe8AZAEpAAcBHwAoAOkAFQGTABQB9ABXANUAEQH0AL0DAwAuAxAA
DAMvADECmwAbAtMACQR2//8EhABGAwYANgABADYAAQAAAAoAJgBAAAJERkxUAA5sYXRuAA4ABAAA
AAD//wACAAAAAQACa2VybgAUbWFyawAOAAAAAQABAAAAAQAAAAIClAAGAAQAAAABAAgAAQJ8AeYA
AgJKAAwATwHUAc4B1AHOAdQBzgHUAc4B1AHOAdQBzgHUAc4ByAJkAcgCZAHCAbwBwgG8AcIBvAHC
AbwBwgG8AbYBsAG2AbABtgGwAbYBsAG2AbABqgGkAaoBpAGeAZgBngGYAZ4BmAGeAZgBngGYAZ4B
mAGeAZgBngGYAZ4BmAGeAZgBngGYAZ4BmAGeAZgBngGYAZIAAAGSAAABkgAAAYwAAAGMAAABhgGA
AYYBgAGGAYABhgGAAYYBgAGGAYABhgGAAYYBgAGGAYABegF0AXoBdAF6AXQBegF0AXoBdAFuAAAB
bgAAAW4AAAFuAAABbgAAAWgBYgFoAWIBXAFWAVwBVgFcAVYBXAFWAVwBVgFcAVYBUAFKAVABSgFE
AAABRAAAAUQAAAFEAAABRAAAAT4AAAE+AAABPgAAAXoAAAF6AAAAAQFQAkQAAQFcAkMAAQFcAAAA
AQFUAkQAAQFZ//4AAQFZAkIAAQFbAAAAAQFTAkQAAQBrAkQAAQFaAAAAAQFaAkQAAQFsAAAAAQFv
AkQAAQGbAtAAAQGSAtAAAQGeAAAAAQGeAtAAAQGTAAAAAQGTAtAAAQBsAAAAAQBtAtAAAQGPAAAA
AQGOAtAAAQG5AtAAAQGiAAAAAQGiAtAAAgAQAAEABwAAAAoACwAHAA0AEQAJABUAGQAOAB4AJQAT
ACgAKAAbACoAKwAcAC0AMQAeADUAQAAjAEMARAAvAEYASgAxAE8AUwA2AFgAXwA7AGQAZQBDAGgA
bABFAHAAdABKAAkAAAAsAAAALAAAACwAAAAsAAAALAAAACwAAAAsAAAALAABACYAAQG5AAAAAQAA
AkQAAgABALEAuQAAAAIACAABAAgAAQB0AAQAAAA1BtIGxAa+BqgGngaIBnoGQAa+BioGGAYOBr4F
9AXiBdgFxgWsBZoFfAVWBUgFJgUcBOIEyASWBHwERgQcA+YD1AOGA3QDagMoAv4C3AKqApgCkgJM
Ah4B6AGiAYgBTgFEARYA/AD2APAA4gABADUAAQAJAAoADAANABIAEwAVABoAGwAcAB0AHgAgACcA
KQAqACwALQAyADMANAA1ADgAOgBCAEMARQBGAEsATABNAE4AVABVAFYAVwBYAFoAYQBiAGMAZABn
AGgAbQBuAG8AcABzAIYAjQCaAAMAVgAOAGcADgBtABwAAQAsAAcAAQBtAAAABgA6/+YARv/nAE3/
+QBW/+cAZ//nAHP/5gALADr/6ABD/+kARv/pAFX/8gBW//wAWP/pAFr/6ABh//kAY//yAGT/+QBu
//kAAgBG/+EAaP/yAA4AOv/rAEP/6wBG/+AATP/eAE3/8gBO//IAVv/5AFj/7QBa/9AAY//RAGT/
1QBn//wAaP/yAHD/7wAGADr/6gBG/+IATgAHAFr/8ABk//gAbQAHABEAQv/pAEP/6QBFAAMARv/q
AEv/7ABM//kAVf/5AFf/5wBYAAIAWv/5AGH/6QBk/+sAZ//qAG7/+QBv/+4Ac//pAJr/8gANADoA
FQBCAAgARQApAE0ADwBOAAIAVwAVAGMABwBkAAcAZwAHAG0AAwBwAAcAcwAPAH8ABwALAEP/7ABG
/+0ATP/4AFX/6gBY/+gAWv/yAGj/4wBt/9wAbv/rAG//5QBz/+gAEQA6AA4AQgAHAEUAFQBGAAcA
SwAOAEwABwBNAAcATgAOAFYABwBYAA4AWgACAGQADgBoAA4AbQAHAHMABwB///oAgP9IAAEAaP/t
AAQARQAIAE4ABQBUAAcAZAADAAwAOv/qAEL/+QBW/+cAWP/nAFr/6QBj/+oAZP/qAGf/7QBo/+YA
bf/pAG7/xABv/+MACABC/+YAQ//pAEb/6wBM//kAWv/qAGH/6QBk//IAb//qAAoAOv/rAEL/6wBD
/+QARv/kAEz/4gBV/9UAV//VAFj/+QBh/9kAbv/JABAAOgAEAEIAAgBFABYARgACAEsABwBOABUA
VgAHAFf//QBYAAcAWgAEAGgACABt/+4Abv/sAHAADgBzAAcAmv/lAAIARv/+AE4ABwAEADoABwBG
//oAVAAcAGgABwATADr/9gBDAAIARQAOAEYABwBL//8ATAAAAE0ADgBVAAcAVgAVAFgAFwBhAAYA
YgAeAGMAFQBkABwAZwAOAG0ABQBuAA4AbwABAHMABwAEADoAAgBG//8ASwADAE4AAgANADr/6gBD
/+sARv/rAEv/+QBM//IAV//5AFr/6gBj/+oAZP/rAGj/5wBu/94AcP/yAHP/+QAKADoABwBFAAcA
TQAHAFQADgBWAA4AWAAOAFoABwBnABYAaAAKAID/hAANAEP/6QBG/+oATP/5AE3/+QBUAAcAVv/o
AFr/8gBj//oAZP/5AG3/0gBu/9oAb//sAHD/+QAGAEb/6gBa/+kAY//5AGj/6ABu//kAcP/yAAwA
Ff/yADr/+QBC//kAQ//5AEb/5wBN/+cAVf/mAFr/+QBj//kAZ//mAGj/5wBz/+YABgA6//kARQAJ
AGj/+QBt//gAbv/wAJoABwAOAEL/5ABD/+UATP/5AE3/+QBV//kAVv/qAFf/5gBY//UAY//sAGT/
6gBt/98Abv/ZAG//7QBz/+QAAgA1//0ARv/rAAgAKv/1ADr/1gBG/7gATv/6AFr/uABh/9QAZP+7
AGj/1gADAAn/5AA6//IARv/yAAkAAf/WACD/2gA6/9IARv++AE3/6wBO/+EAWv/LAGj/0ABw//IA
BwAB/+0AIP/2ACr/+gBG/94ATgAHAFr/1ABk/80ABABk//kAbf/yAG7/+QBv//kABgBa/8oAZP/M
AGj/4QBu/+YAcP/kAHP/4AAEAB7/5gAz/+EANf/9AG7/6wACADL/4wAz/+MABAABAAMAGv+yAEUA
AwBtAAAABgAy/98AM//fADT/3wBD//IATP/5AHP/8gACADr/+QBD/+8ABAAy/y4AM/+LADX/VwBW
AAcABQAB/+cAFP/pADr/+QBa/+sAcP/5AA4AGgAVABsABwAsAA4AOgAOAEIABwBYAA4AWgAHAGEA
DgBiAA4AYwAHAGQABwBtAB4AbgAHAG8ADgADADP/3wA1//QARQAHAAUAGv8yACkAAgAsAAoAcP/6
AH//2AACAB3/6gAg/+sABQAd//IAMv/dADP/6wA4/+UATv/5AAEARv/5AAMAMv/IADX/2gBN//kA
AgAz/9sANf/tAAIAFAAAAeAC0AAEAAkAACExJREhAzERIREB4P40Acwi/ngBAs/9UgKM/XQAAgA6
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
AAAXMTUlJTUFFTsBBP78AaQJmJeWl/J3AAEABf/5AagCVQAHAAAFMSU1JRUFBQGo/l0Bo/78AQQH
83fylpeXAAABABgA3QGEAXkAEgAAJSInJiMiBzU2MzIXFjMyNxUGIwErJDw+JCcqLSgmREMYIDI0
Jd0gIB1mEyAhHmQVAAUAMAAAA5QC0AAGABsALABBAFIAADMxNQE3FQETIiYmNTU0NjYzMzIWFhUV
FAYGIyMnMTMyNjU1NCYjIyIGFRUUFgEiJiY1NTQ2NjMzMhYWFRUUBgYjIycxMzI2NTU0JiMjIgYV
FRQWhwKjJv1fBSY8IiI8JlUmOyIiOyZVBFwJDg4JXAoNDQIVJTsiIjslViY7IiI7JlYCWwoNDQpb
Cg0NjgI/A439wgFzIzsmTCY7ISE7JkwmOyNqDQpRCg0NClEKDf4kIjsmTCY7IiI7JkwmOyJpDQpS
Cg0NClIKDQAAAgA2AAAC/wLQAC8APAAAMyImJjURNDY2MyEyFhYVESEiJiY1NTQ2NjMzMhYWFRUz
ETQmIyEiBhURFBYzIRUhEzM1NCYjIyIGFRUUFsAmPiYmPiYBtSY/Jf54JjgfHzgmSCY4HkEHBf5V
BQcHBQI6/cGjfAcFcAUICCY+JgG8Jz4lJT4n/oseNyc+JjgeHjgmWAEOBQcHBf5OBQeDATNsBQcH
BWAFBwAAAgA1//kDdgLPACkANgAAMyImJjU1NDY3JjU1NDY2MyEyFhYXFSM1NCYjISIGFRUFNTMV
FxUnBgYjJSEyNjclJyIGFRUUFr8mPiYgHBYmPiUBcyE7KAaDBwX+mAUHAZ2DeIsTQCT+UAFdCxQJ
/osPBgcHJT4nwhYuChkpaSc/JB40IE0vBQcHBXbQbaNHg08gKIMGBbwGEhuUBQcAAwA4AAADDwLG
ABIAHAAhAAAhMTUjIiYmNTU0NjYzIREjNSMVATM1IyIGFRUUFiExMzUjAbDuJj4mJj4mAk2DWP6T
6ekFBwcBclhY9CY+Jr4lQCX9OvT0AXjKBwWyBQfKAAACAC0BaQGWAskAFAAkAAATIiYmNTU0NjYz
MzIWFhUVFAYGIyMnMzI2NTU0JiMjIgYVFRQWuCc+JiY+J1UlPyUlPyVVD3EFBwcFcQUHBwFpJj8l
TCY/JSU/JkwlPyZxBwVmBQgIBWYFBwAAAQA2/5gAuQMwAAQAABcxETMRNoNoA5j8aAAC/1kCgACo
AwQABAAJAAATMTUzFSExNTMVJIT+sYMCgISEhIQAAAH/vgKAAEIDBAADAAADNTMVQoQCgISEAAH/
lwKAAEsDNwAEAAADMSczFzsuhi4CgLe3AAAB/7cCgABqAzcABAAAAzE3MwdJL4QtAoC3twAAAf9t
AokAlQMzAAcAAAMxNzMXIycHk2VeZXAlJAKJqqo/PwAAAf9yAoAAjQMjAAcAAAMxJzMXNzMHK2No
JSVpYQKAozk5owAAAv+gAocAYANDAA8AHwAAAyImNTU0NjMzMhYVFRQGIyczMjY1NTQmIyMiBhUV
FBYaHCoqHDUcKSkcNjYCAQECNgIBAQKHKBwzHCkpHDMcKDwBAjcCAgICNwIBAAAB/0oCkgC2A0wA
DgAAEyInJiMjNTMyFxYzMxUjXTc7OShATzM2Ni5QWQKSKyplLCxiAAEBU/9pAggADwADAAAFNzMH
AVMwhS+Xpqb//wBkAoABtAMEAAcAsQELAAD//wBJAoAAzQMEAAcAsgCLAAD//wA7AoAA7gM3AAcA
swCjAAD//wAmAoAA2QM3AAYAtG4A//8AZAKJAYsDMwAHALUA9wAA//8ABwKAASIDIwAHALYAlQAA
AAEAKAMSAQgDggAQAAATIiY1MxQWFzM2NjUzFAYjI4MqMVAEAzYCAk8xIzEDEjQ8Dw8BAQ8PPDT/
/wAVAvMA1AOvAAYAt3Vs//8AFAKSAYADTAAHALgAygAAAAEAVwJ+AZsC0AAEAAATMTUhFVcBRAJ+
UlL//wAR/2kAxgAPAAcAuf6+AAAAAQC9/wYBN//vAAQAABcxNTMVvXr66ekAAQAuAAAC9gLQAAgA
ADMxNQEhNSEVAS8BzP4zAsj9xiMCKoMj/VMAAAIADAAAAtYCzwAVACIAACE1NCYmIyEiJiY1NTQ2
NjMhMhYWFREBITU0JiMhIgYVFRQWAlMDDxH+Zyc+JiY+JwG1Jj4m/cYBtwgF/lYFBwf8Ew0DJT8m
myc+JiY+J/28AaKdBQcHBZEFBwABADEAAAL5AtAAHAAAMyImJycBNSEiBhUVIzU0NjYzITIWFhcV
ARUhFSG6MUwLAQJF/ksFB4QmPicBtSE5KAb9vAJE/cE+LYEBNCwHBTxCJj4mHzQfjv7MGYMAAAIA
GwAAAoMC0AAkACgAADc1NDY2MzMyNjU1NCYjIRUjNT4CMyEyFhYVFRQGBiMjIgYVFQc1MxW6Jj4m
sAUHBwX+qoMGJjoiAVYmPiYmPyWvBQeEhLJVJz4lBwWkBQdndyA0HyU+J68lPyYHBU+yg4MAAAEA
CQAAArYCzwAQAAAhMTUhNQEzFQEhNTMVMxUjFQHO/jsBZHv+ywEbg2VltHoBoUP+q46Og7QAAf//
AAAEPQLQABAAACExATUzATUDNTMBETMRIwMRAkD9v5ABvN+PAb2FkNwCrCT98uQBBSX98QIP/TAB
Bv76AAEARgAABIQC0AAQAAAzMREzEQEzFQMVATMVASMRA0aFAb2P3wG8kP3AkdwC0P3wAhAl/vvm
AhAk/VQBBv76AAABADYAAAL+AtAACAAAMzERMxEBMxUBNoMBuI39xwLQ/e4CEiz9XAAAAgABAAAC
yQLQAAkADQAAMzE1ATMRIzUhBwExMzUBAjmPhP7imQEHsCMCrf0wt7cBOs4AAAIANgAAAv4C0AAJ
AA0AADMxETMBFSMnIRURMTMnNo8COY2b/uOwsALQ/VMjt7cBOs4=
FIN_B64
    else
        tr -d '\n' <<'FIN_B64'
AAEAAAAQAQAABAAAR0RFRgRJBGkAAAJMAAAAdkdQT1PxqNIJAAAPNAAACaxHU1VCuPy46gAAAWAA
AAAoT1MvMmIkzDMAAAHsAAAAYFNUQVR5lWwRAAABiAAAACpjbWFwyaNyCQAACVAAAAKmZ2FzcAAA
ABAAAAEUAAAACGdseWYMB+JGAAAY4AAAKRRoZWFkCoGkywAAAbQAAAA2aGhlYQg9AyMAAAE8AAAA
JGhtdHjw8h3NAAAL+AAAAzxsb2NhEFMGNgAAAsQAAAGibWF4cADcAJgAAAEcAAAAIG5hbWUyBV6J
AAAG2AAAAnhwb3N07p4E4gAABGgAAAJtcHJlcGgGjIUAAAEMAAAAB7gB/4WwBI0AAAEAAf//AA8A
AQAAANAAUwAFAEMABAABAAAAAAAAAAAAAAAAAAIAAQABAAAD8/8NAAAFX/9E/egFAwABAAAAAAAA
AAAAAAAAAAAAzgABAAAACgAmACYAAkRGTFQAEmxhdG4ADgAAAAAABAAAAAD//wAAAAAAAQABAAgA
AQAAABQAAQAAABwAAndnaHQBAAAAAAIAAQAAAAABBgOEAAAAAAABAAAAAgBCqMVeRl8PPPUAAwPo
AAAAAMoDDTEAAAAA3R9Tk/9E/wYFAwPcAAAABgACAAAAAAAAAAQChwOEAAUAAAKKAlgAAABLAooC
WAAAAV4AMgFcAAAAAAAAAAAAAAAAgAAAZxAAAEIAAAAAAAAAAE5PTkUAwAAg4AwD8/8NAAAD8wDz
AAAAAQAAAAACRALQAAAAIAACAAEAAAAMAAAAAAAAAAIAEQABAAcAAQAKAAsAAQANABEAAQAVABkA
AQAeACUAAQAoACgAAQAqACsAAQAtADEAAQA1AEAAAQBDAEQAAQBGAEoAAQBPAFMAAQBYAF8AAQBk
AGUAAQBoAGwAAQBwAHQAAQCxALkAAwAAAAAAFgA9AEkAVQBhAG0AeQCFALAA6wEOARkBPgFUAWAB
bAF4AYQBmAHLAeIB7gH6AgYCEgIeAjwCWQJoAoEClwKjAtIC3gLqAvYDAgMOAz0DYwOaA8gECQQV
BCgESARUBGAEbAR4BI0EqwTLBOIE7gT6BRAFHAVCBU4FWgVmBXIFfgWKBcAF6AYIBhMGOwZoBnQG
gAaMBpgGsQboBwUHGAclBzAHOwdGB1EHbQeHB50HvwfaB+YIFggiCC4IOghGCFIIjgi2COAI9gk4
CUQJewmVCbUJwQnNCdkJ5Qn5ChYKMgpYCmQKcAqGCpIKxQrWCwoLSwtnC5cLzAvjDC8Magx2DIcM
mgyxDMgM2wzuDRsNSA1dDXoNqg27DcwN6g4IDi4OVA5lDnYOgw6QDp0Oqg7HDuMO9Q8GDxkPJg8m
DyYPWA+GD9wQBxAbECgQRBBeEHIQgxCWELURJBFsEbMR4BINEhoSLRI5EkcSVRJnEnkSnxK4EsUS
zhLXEuAS6BLxEvoTFRMdEyYTMxM8E0gTXBOME7gT6xQHFCYURBRYFHEUigAAAAIAAAAAAAD/nAAy
AAAAAAAAAAAAAAAAAAAAAAAAAAAA0AAAACQAyQDHAGIArQBjAK4AkAAlACYAZAAnACgAZQDIAMoA
ywApACoAKwAsAMwAzQDOAM8ALQAuAC8AMAAxAGYAMgDQANEAZwDTAK8AsAAzADQANQA2AOQANwA4
ANQA1QBoANYAOQA6ADsAPADrALsAPQDmAEQAaQBrAGwAagBuAG0AoABFAEYAbwBHAEgAcAByAHMA
cQBJAEoASwBMANcAdAB2AHcAdQBNAE4ATwBQAFEAeABSAHkAewB8AHoAfQCxAFMAVABVAFYA5QCJ
AFcAWAB+AIAAgQB/AFkAWgBbAFwA7AC6AF0A5wATABQAFQAWABcAGAAZABoAGwAcABEADwAdAB4A
qwAEAKMAIgCiAIcADQAGABIAPwALAAwAXgBgAD4AQAAQALIAswBCALQAtQC2ALcABQAKAAMBAgED
AIQABwCFAA4A7wDwALgAIAAhAB8AYQAIACMACQCIAIMAXwEEAQUBBgEHAQgBCQEKAQsBDACOANwA
QwCNANgA4QDbAN0A2QDaAN4A4AENAQ4BDwEQAREBEgETARQBFQEWB3VuaTAwQTAERXVybwd1bmkw
MzA4B3VuaTAzMDcJZ3JhdmVjb21iCWFjdXRlY29tYgd1bmkwMzAyB3VuaTAzMEMHdW5pMDMwQQl0
aWxkZWNvbWIHdW5pMDMyNwd1bmlFMDAyB3VuaUUwMDMHdW5pRTAwNQd1bmlFMDA2B3VuaUUwMDcH
dW5pRTAwOAd1bmlFMDA5B3VuaUUwMEEHdW5pRTAwQgd1bmlFMDBDAAAAAAAADACWAAMAAQQJAAAA
9gDsAAMAAQQJAAEAHADQAAMAAQQJAAIADgDCAAMAAQQJAAMAMgCQAAMAAQQJAAQAHADQAAMAAQQJ
AAUAGgB2AAMAAQQJAAYAHABaAAMAAQQJAA4ANAAmAAMAAQQJABAAEAAWAAMAAQQJABEACgAMAAMA
AQQJAQAADAAAAAMAAQQJAQYACgAMAFcAZQBpAGcAaAB0AEIAbABhAGMAawBPAHIAYgBpAHQAcgBv
AG4AaAB0AHQAcAA6AC8ALwBzAGMAcgBpAHAAdABzAC4AcwBpAGwALgBvAHIAZwAvAE8ARgBMAE8A
cgBiAGkAdAByAG8AbgAtAEIAbABhAGMAawBWAGUAcgBzAGkAbwBuACAAMgAuADAAMAAxADIALgAw
ADAAMQA7AE4ATwBOAEUAOwBPAHIAYgBpAHQAcgBvAG4ALQBCAGwAYQBjAGsAUgBlAGcAdQBsAGEA
cgBPAHIAYgBpAHQAcgBvAG4AIABCAGwAYQBjAGsAQwBvAHAAeQByAGkAZwBoAHQAIAAyADAAMQA4
ACAAVABoAGUAIABPAHIAYgBpAHQAcgBvAG4AIABQAHIAbwBqAGUAYwB0ACAAQQB1AHQAaABvAHIA
cwAgACgAaAB0AHQAcABzADoALwAvAGcAaQB0AGgAdQBiAC4AYwBvAG0ALwB0AGgAZQBsAGUAYQBn
AHUAZQBvAGYALwBvAHIAYgBpAHQAcgBvAG4AKQAsACAAdwBpAHQAaAAgAFIAZQBzAGUAcgB2AGUA
ZAAgAEYAbwBuAHQAIABOAGEAbQBlADoAIAAiAE8AcgBiAGkAdAByAG8AbgAiAC4AAAACAAAAAwAA
ABQAAwABAAAAFAAEApIAAABOAEAABQAOAC8AOQBdAH4AowCoALAAtAC2ALgAzwDXAN0A7wD3AP0A
/wExAVMBYQF4AX4CxwLcAwMDCAMKAwwDJyAUIBkgHSAiICYgrCIS4APgDP//AAAAIAAwADoAXwCg
AKgArwC0ALYAuAC/ANEA2QDfAPEA+QD/ATEBUgFgAXgBfQLGAtgDAAMHAwoDDAMnIBMgGCAcICIg
JiCsIhLgAuAF//8AAABFAAAAAAAAABIAAAAJ//gADAAAAAAAAAAAAAAAAP9z/x4AAAAA/r8AAP34
AAAAAAAA/a39qv2S4IHggeB74GbgXd/z3pIgxCDDAAEATgAAAGoAsADuAAAA8gAAAAAAAADuAQ4B
GgEiAUIBTgAAAAABUgFUAAABVAAAAVQBXAFiAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAnQCE
AJsAigChAKsArQCcAI0AjgCJAKMAgACTAH8AiwCBAIIAqQCnAKgAhgCsAAEACQAKAAwADQASABMA
FAAVABoAGwAcAB0AHgAgACcAKAApACoALAAtADIAMwA0ADUAOACRAIwAkgCWALwAOgBCAEMARQBG
AEsATABNAE4AVABVAFYAVwBYAFoAYQBiAGMAZABnAGgAbQBuAG8AcABzAI8AsACQAKoAngCFAKAA
ogDDAK8AhwAFAAIAAwAHAAQABgAIAAsAEQAOAA8AEAAZABYAFwAYAB8AJAAhACIAJQAjAKUAMQAu
AC8AMAA2AGYAPgA7ADwAQAA9AD8AQQBEAEoARwBIAEkAUwBQAFEAUgBZAF4AWwBcAF8AXQCmAGwA
aQBqAGsAcQAmAGAAKwBlADkAdADAALsAwQDFAMIAswC0ALUAuACyALEAAAH0ABQDRAA6A0QAOgNE
ADoDRAA6A0QAOgNEADoDRAA6BV8ANgNAADsDNgA4AzYAOANCADoC/gA6Av4AOgL+ADoC/gA6Av4A
OgLTADoDPgA4A1MAOQDWAB8A1gAZANb/zgDW/7YA1v/0AwwABAMdADkDCwA5A6AAOANAADgDQAA4
AzwANgM8ADYDPAA2AzwANgM8ADYDPAA2BV4ANQMXADgDdAA2AzkAOAM8ADYDPAA2AvcAFAM8ADYD
PAA2AzwANgM8ADYDPAA2A+sAIwSbACMDLAAuAyb/9wMm//cDJv/3AzUAMwM1ADMCtgA0ArYANAK2
ADQCtgA0ArYANAK2ADQCtgA0BJoANAKbADYCtwAzArcAMwKbABcCtAAzArQAMwK0ADMCtAAzArQA
MwG4ADUCqwApApwANgDlADQA1gAfANYAFwDW/8wA1v+0ANb/8gDv/0UChgA2AVEANAPSADYCuAA2
ArgANgK0ADMCtAAzArQAMwK0ADMCtAAzArQAMwSZADQCmAA2ApgAFAIOADQCrgAwAq4AMANBADkB
wwA1ArcANQK3ADUCtwA1ArcANQK3ADUDFgAVBB0AIwK0AC4CrQAqAq0AKgKtACoCugA2AroANgNC
ADkBhwABAz4AOQM6ADUC2gAGAz4AOQM0ADkClAADA0IAOQM8ADMA6QA2APMANgD3ADYBCgAzAj4A
NgDcADoA0gA1AqYAHwKjABMBcwBsAgQAGQMdACACCQAGAggABQEmADQBKQA4ASEAFwEhADMBEwA2
ARQAMwIFADsCxAA2AzYANgM8ADYB0gAtAdIANgDwACIA7gA2AYwAJAD7ADsBQgAAAUIAAAMfACMC
fAAhAxQAIgLeACcBxwARAgUAOwIiADUCBwAHAn4AOwHbADsB2QAFAZQAGAPGADADLwA2A6oANQNB
ADgBtwAtANYANgAA/0kAAP+zAAD/hwAA/6wAAP9hAAD/YAAA/5oAAP9EAAABRwI3AGQBKgBIARAA
JwDVABwCCABkASn/9QEfACgA6QAPAZMADgH0AFcA1QAEAfQAvQMDAC4DEAAMAy8AMQKbABsC0wAJ
BGv//wR9AFADBgA2AAAANgABAAAACgAmAEAAAkRGTFQADmxhdG4ADgAEAAAAAP//AAIAAAABAAJr
ZXJuABRtYXJrAA4AAAABAAEAAAABAAAAAgKIAAYABAAAAAEACAABAnAB2gACAj4ADABPAcgBwgHI
AcIByAHCAcgBwgHIAcIByAHCAcgBwgG8AlgBvAJYAbYBsAG2AbABtgGwAbYBsAG2AbABqgNsAaoD
bAGqA2wBqgNsAaoDbAGkAZ4BpAGeAZgBkgGYAZIBmAGSAZgBkgGYAZIBmAGSAZgBkgGYAZIBmAGS
AZgBkgGYAZIBmAGSAZgBkgGYAZIBjAAAAYwAAAGMAAABhgAAAYYAAAGAAXoBgAF6AYABegGAAXoB
gAF6AYABegGAAXoBgAF6AYABegF0AW4BdAFuAXQBbgF0AW4BdAFuAWgAAAFoAAABaAAAAWgAAAFo
AAABYgFcAWIBXAFWAVABVgFQAVYBUAFWAVABVgFQAVYBUAFKAW4BSgFuAUQAAAFEAAABRAAAAUQA
AAFEAAABYgAAAWIAAAFiAAABPgAAAT4AAAABAVwCRAABAVsCQwABAVQCRAABAVn//gABAVkCQgAB
AVwAAAABAVACRAABAGsCRAABAVkAAAABAVkCRAABAWwAAAABAW8CRAABAZsC0AABAZIC0AABAZ4A
AAABAZ4C0AABAZMAAAABAZMC0AABAG0C0AABAY4AAAABAY4C0AABAbkC0AABAaIAAAABAaIC0AAC
ABAAAQAHAAAACgALAAcADQARAAkAFQAZAA4AHgAlABMAKAAoABsAKgArABwALQAxAB4ANQBAACMA
QwBEAC8ARgBKADEATwBTADYAWABfADsAZABlAEMAaABsAEUAcAB0AEoACQAAACwAAAAsAAAALAAA
ACwAAAAsAAAALAAAACwAAAAsAAEAJgABAbkAAAABAAACRAACAAEAsQC5AAAAAgAIAAEACAABAHQA
BAAAADUG0gbEBr4GqAaeBogGegZABr4GKgYYBg4GvgX0BeIF2AXGBawFmgV8BVYFSAUmBRwE4gTI
BJYEfARGBBwD5gPUA4YDdANqAygC/gLcAqoCmAKSAkwCHgHoAaIBiAFOAUQBFgD8APYA8ADiAAEA
NQABAAkACgAMAA0AEgATABUAGgAbABwAHQAeACAAJwApACoALAAtADIAMwA0ADUAOAA6AEIAQwBF
AEYASwBMAE0ATgBUAFUAVgBXAFgAWgBhAGIAYwBkAGcAaABtAG4AbwBwAHMAhgCNAJoAAwBWABQA
ZwAUAG0AKAABACwACgABAG0AAAAGADr/5QBG/+cATf/2AFb/5QBn/+UAc//jAAsAOv/nAEP/5wBG
/+cAVf/sAFb/9gBY/+UAWv/nAGH/9gBj/+wAZP/2AG7/9gACAEb/6QBo/+wADgA6/+IAQ//iAEb/
4ABM/88ATf/sAE7/7ABW//YAWP/lAFr/xABj/8UAZP/JAGf/+gBo/+wAcP/nAAYAOv/gAEb/4gBO
AAoAWv/2AGQAAABtAAoAEQBC/+UAQ//nAEUAAABG/+cAS//nAEz/9gBV//YAV//lAFgAAABa//YA
Yf/lAGT/6QBn/+cAbv/2AG//7QBz/+UAmv/sAA0AOgAeAEIACgBFADIATQAUAE4AAABXAB4AYwAK
AGQACgBnAAoAbQAFAHAACgBzABQAfwAKAAsAQ//rAEb/6wBM//UAVf/nAFj/5wBa/+wAaP/fAG3/
1QBu/+IAb//pAHP/5wARADoAFABCAAoARQAfAEYACgBLABQATAAKAE0ACgBOABQAVgAKAFgAFABa
AAUAZAAUAGgAFABtAAoAcwAKAH8AAACA/2MAAQBo/+8ABABFAAAATgAAAFQACgBkAAAADAA6/+UA
Qv/2AFb/5QBY/+MAWv/nAGP/5QBk/+kAZ//vAGj/5QBt/+UAbv+5AG//5QAIAEL/4wBD/+cARv/i
AEz/9gBa/+cAYf/jAGT/7ABv/+sACgA6/+EAQv/iAEP/2ABG/9gATP/VAFX/xwBX/8cAWP/2AGH/
xwBu/7sAEAA6AAsAQgADAEUAHgBGAAoASwAKAE4AHgBWAAoAVwAAAFgACgBaAAoAaAALAG0AAABu
AAAAcAAUAHMACgCaAAAAAgBGAAAATgAKAAQAOgAKAEYAAABUACgAaAAKABMAOgABAEMACgBFABQA
RgAKAEsAFABMAAAATQAUAFUACgBWAB4AWAAoAGEAFABiADIAYwAeAGQAKABnABQAbQAKAG4AFABv
ABQAcwAKAAQAOgAAAEb//wBLAAAATgAAAA0AOv/nAEP/6QBG/+kAS//2AEz/7ABX//YAWv/pAGP/
5wBk/+sAaP/nAG7/1wBw/+wAc//2AAoAOgAKAEUACgBNAAoAVAAUAFYAFABYABQAWgAKAGcAHgBo
AAoAgP+dAA0AQ//nAEb/5wBM//YATf/2AFQACgBW/+YAWv/sAGP/+QBk//YAbf/HAG7/1wBv/+sA
cP/2AAYARv/pAFr/6QBj//YAaP/nAG7/9gBw/+wADAAV/+wAOv/2AEL/9gBD//YARv/nAE3/4wBV
/+MAWv/2AGP/9gBn/+UAaP/lAHP/4wAGADr/9gBFAAAAaP/2AG3/9QBu/+kAmgAKAA4AQv/jAEP/
3QBM//YATf/2AFX/9gBW/+UAV//jAFj/9wBj/+UAZP/pAG3/2QBu/9UAb//rAHP/4wACADUAAABG
/+IACAAqAAAAOv/vAEb/zQBOAAAAWv/NAGH/7QBk/9EAaP/vAAMACf/nADr/7ABG/+wACQAB/88A
IP/TADr/xABG/7AATf/iAE7/2ABa/78AaP/EAHD/6wAHAAH/9QAgAAAAKgAAAEb/zgBOAAoAWv/O
AGT/yAAEAGT/9gBt/+wAbv/2AG//9gAGAFr/6QBk/+sAaAAAAG4AAABwAAAAcwAAAAQAHv/jADP/
3wA1AAAAbv/iAAIAMv/fADP/3wAEAAEAAAAa/+MARQAAAG0AAAAGADL/3QAz/90ANP/hAEP/7ABM
//YAc//sAAIAOv/2AEP/7AAEADL/NwAz/5EANf9bAFYACgAFAAH/6QAU/+sAOv/2AFr/4gBw//YA
DgAaAB4AGwAKACwAFAA6ABQAQgAKAFgAFABaAAoAYQAUAGIAFABjAAoAZAAKAG0ALABuAAoAbwAU
AAMAM//dADX/7wBFAAoABQAa/0IAKQAAACwACgBwAAAAfwAAAAIAHf/tACD/7wAFAB3/7AAy/9sA
M//iADj/5QBO//YAAQBG//YAAwAy/8UANf/XAE3/9gACADP/2QA1/+sAAgAUAAAB4ALQAAQACQAA
ITElESEDMREhEQHg/jQBzCj+hAECz/1YAoD9gAACADoAAAMKAtAAEAAbAAAzETQ2NjMhMhYWFREj
NSEVIxMhNTAwMSEwMDEVOihEKAGnKUMpnf5om5sBmP5oAjwpQygoQyn9xOjoAYSwsP//ADoAAAMK
A9cCJgABAAAABwC0AaIAjP//ADoAAAMKA8QCJgABAAAABwC1AaIAjP//ADoAAAMKA6YCJgABAAAA
BwCxAaIAjP//ADoAAAMKA9cCJgABAAAABwCzAaIAjP//ADoAAAMKA9UCJgABAAAABwC3AaIAjP//
ADoAAAMKA9wCJgABAAAABwC4AaIAjAACADYAAAUDAtAAFAAfAAAzMRE0NjYzIRUhFSEVIRUhFSE1
IRURMSE1MDAxITAwMTYpQygEOf4DAZn+ZwH9/Wj+aAGY/mgCPClDKJx+nH6c6OgBhLAAAAMAOwAA
AwsC0AATACMAMwAAMxEhMhYWFRUUBgcWFhUVFAYGIyE3ITAwMTUwMDEhMDAxFTAwESEwMDE1MDAx
ITAwMRUwMDsCIChDKQMEDxQpQyn9xZsBmP5oAXz+hALQKEMphw0XChMyGZUoRCichIQBIHh4AAAB
ADgAAAMGAtAAFQAAMyImJjURNDY2MyEVISIGFREUFjMhFcwpQygoQykCOv3uEBEREAISKEMpAagp
QyicEBH+qhARnAD//wA4/2QDBgLQAiYACgAAAAYAuQAAAAIAOgAAAwoC0AALABsAADMRITIWFhUR
FAYGIyUhMDAxETAwMSEwMDERMDA6AjspQykpQyn+XwGZ/mcC0ChDKf5YKEQonAGY/mgAAQA6AAAC
0wLQAAsAADMRIRUhFSEVIRUhFToCmf4EAZn+ZwH8AtCcfpx+nP//ADoAAALTA9cCJgANAAAABwC0
AY4AjP//ADoAAALTA8QCJgANAAAABwC1AY4AjP//ADoAAALTA6YCJgANAAAABwCxAY4AjP//ADoA
AALTA9cCJgANAAAABwCzAY4AjAABADoAAALTAtAACQAAMxEhFSEVIRUhEToCmf4EAZn+ZwLQnH6c
/uYAAQA4AAADCALQACkAADMiJiY1ETQ2NjMhMhYWFRUjNTAwMSEwMDERMDAxITAwMTUjNSERFAYG
I8woRCgoRCgBpylDKZ3+aAGYnAE5KUMpKEQoAagpQygoQylEPP5obJz+8ChEKAAAAQA5AAADGALQ
AAsAADMRMxEhETMRIxEhETmbAambm/5XAtD+5gEa/TABGv7mAAEAHwAAALgC0AADAAAzETMRH5kC
0P0w//8AGQAAAOkD1wImABUAAAAHALQAbQCM////zgAAAQ4DxAImABUAAAAHALUAbQCM////tgAA
ASUDpgImABUAAAAHALEAbQCM////9AAAAMQD1wImABUAAAAHALMAbQCMAAEABAAAAtQC0AAVAAAz
IiYmNTUzFTAwMSEwMDERMxEUBgYjmChEKJsBmJ0pQygoRChdVQI0/cQoRCgAAAEAOQAAAvAC0AAO
AAAzETMRMxMzFQEBFSMDIxE5nI3sov7/AQGi7I0C0P7mARo2/s7+zjYBGv7mAAABADkAAAMJAtEA
BQAAMxEzESEVOZsCNQLR/cucAAABADgAAANgAtAACwAAMxEzExMzESMRAwMROKD086Gc+PkC0P7d
ASP9MAHj/tgBJ/4eAAEAOAAAAwgC0AAJAAAzETMBETMRIwEROKABk52g/msC0P4gAeD9MAHi/h7/
/wA4AAADCAPcAiYAHgAAAAcAuAGTAIwAAgA2AAADBgLQABMAIwAAMyImJjURNDY2MyEyFhYVERQG
BiMlITAwMREwMDEhMDAxETAwyihEKChEKAGoKEMpKUMo/l8BmP5oKEQoAagpQygoQyn+WChEKJwB
mP5o//8ANgAAAwYD1wImACAAAAAHALQBngCM//8ANgAAAwYDxAImACAAAAAHALUBngCM//8ANgAA
AwYDpgImACAAAAAHALEBngCM//8ANgAAAwYD1wImACAAAAAHALMBngCM//8ANgAAAwYD3AImACAA
AAAHALgBngCMAAIANQAABQIC0AATACMAADMiJiY1ETQ2NjMhFSEVIRUhFSEVJSEwMDERMDAxITAw
MREwMMkoRCgoRCgEOf4DAZn+ZwH9+9ABmP5oKEQoAagpQyicfpx+nJwBmP5oAAACADgAAAMIAs8A
DQAdAAAzESEyFhYVFRQGBiMFFREhMDAxNTAwMSEwMDEVMDA4AjspQykpQyn+YAGY/mgCzyhEKLoo
RCgB7AGJq6sAAwA2AAADWALQAAUAGQApAAAhNTcxMxUhIiYmNRE0NjYzITIWFhURFAYGIyUhMDAx
ETAwMSEwMDERMDACbJpS/XIoRCgoRCgBqChDKSlDKP5fAZj+aJAMnChEKAGoKUMoKEMp/lgoRCic
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
NTM1MxUzFSMVk4KCmYaGVoWZg4OZhQABADsA2wHcAXQABAAANzE1IRU7AaHbmZkAAAEANQBSAfsC
BAAQAAA3MTU3JzUzFzczFQcXFSMnBzWBgZ5ERZ+Cgp9FRVIyqKYyXl4ypqgyXV0AAwAHAAAB8QJo
AAQACQAOAAA3MTUhFQUxNTMVAzE1MxUHAer+xpmZmfCZmfCZmQHOmpoAAAIAOwCBAkkB5AAEAAkA
ABMxNSEVBTE1IRU7Ag798gIOAUuZmcqZmQABADv/7QHnAl0ABwAAFzE1Nyc1BRU76ekBrBOyh4ax
94EAAQAF/+8BsAJfAAcAAAUxJTUlFQcXAbD+VQGr6uoR+ID4sIeIAAABABgA0gGPAYMAEgAAJSIn
JiMiBzU2MzIXFjMyNxUGIwEsJDo7IiYzNSomQUEYIDg8J9IfHieEFx8fJH4ZAAUAMAAAA40CzwAG
ABsALABBAFIAADMxNQEzFQEDIiYmNTU0NjYzMzIWFhUVFAYGIyM3MTMyNjU1NCYjIyIGFRUUFgEi
JiY1NTQ2NjMzMhYWFRUUBgYjIzcxMzI2NTU0JiMjIgYVFRQWhgKQM/1wASg9IyM9KFEoPSMjPShR
FiQOExMOJA4TEwH0Jz0jIz0nUSg9IyM9KFEXJA4TEw4kDhMTnQIynP3NAXEjPShIKD0iIj0oSCg9
I34TDhoOExMOGg4T/hojPShIKD0iIj0oSCg9I30TDhsOExMOGw4TAAIANgAAAvkC0AAvADwAADMi
JiY1ETQ2NjMhMhYWFREhIiYmNTU0NjYzMzIWFhUVMzUwMDEhMDAxETAwMSEVIRMzNTAwMSMwMDEV
MDDIKEIoKEIoAZ8oQij+gCg4Hh44KD4oOB0s/m8CKv3PnWVlKEInAa4oQicnQij+mR04KDUoOB0d
OCg/7P5imQFLUlIAAAIANf/uA2oCzwApADYAADMiJiY1NTQ2NyY1NTQ2NjMhMhYWFxUjNTAwMSEw
MDEVBTUzFRcVJwYGIyUhMjIzJSciFBUVMDDGJ0IoFhUHKEInAWEjPioGmf6vAWyZc4wVQCP+aAEg
CxMK/skPAidBKbkWMA4RJGspQiYfNiJYNWy3X6FEnlAcIpmdCBAfdgADADgAAAMPAsIAEgAcACEA
ACExNSMiJiY1NTQ2NjMhESM1IxUBMzUjMDAxFTAwITEzNSMBmtAoQigoQigCRZlC/p3JyQFjQkLo
KEIntydDKP0+6OgBgqampgACAC0BVwGhAsIAFAAkAAATIiYmNTU0NjYzMzIWFhUVFAYGIyMnMzAw
MTUwMDEjMDAxFTAwvyhCKChCKFEnQigoQidRC2ZmAVcoQihIKEInJ0IoSChCKIhcXAABADb/nQDP
AyQABAAAFzERMxE2mWMDh/x5AAL/SQKAALgDGgAEAAkAABMxNTMVITE1MxUemv6RmQKAmpqamgAA
Af+zAoAATQMaAAMAAAM1MxVNmgKAmpoAAf+HAoAAVwNLAAQAAAMxJzMXRjOdMwKAy8sAAAH/rAKA
AHwDSwAEAAADMTczB1QznTMCgMvLAAAB/2ECgAChAzgABwAAAzE3MxcjJwefbmRuhhwZAoC4uCws
AAAB/2ACgACgAzgABwAAAzEnMxc3MwcyboMbG4duAoC4LCy4AAAC/5oCgABmA0kADwAfAAADIiY1
NTQ2MzMyFhUVFAYjJzMwMDE1MDAxIzAwMRUwMBkfLi4fMx8tLR8zMjICgC0fMR8tLR8xHy1FNjYA
Af9EAogAvANQAA4AABMiJyYjIzUzMhcWMzMVI1Y5NjQiTVk3Ly8tXWYCiCoqdCsrcgABAUf/ZAIY
AA8AAwAABTczBwFHNJ00nKur//8AZAKAAdMDGgAHALEBGwAA//8ASAKAAOIDGgAHALIAlQAA//8A
JwKAAPcDSwAHALMAoAAA//8AHAKAAOwDSwAGALRwAP//AGQCgAGkAzgABwC1AQMAAP////UCgAE1
AzgABwC2AJUAAAABACgC6wEaA3AAEAAAEyImNTcUFBUzNDQ1MxQGIyOPMDdmJ2U4JS4C6zpKAQ4P
AQEPDks6AP//AA8C7ADbA7UABgC3dWz//wAOAogBhgNQAAcAuADKAAAAAQBXAn4BmwLQAAQAABMx
NSEVVwFEAn5SUv//AAT/ZADVAA8ABwC5/r0AAAABAL3/BgE3/+8ABAAAFzE1MxW9evrp6QABAC4A
AALxAtAACAAAMzE1ASE1IRUBLgGm/loCw/3ZMwIEmTL9YgAAAgAMAAACzwLPABUAIgAAITU0NgYj
ISImJjU1NDY2MyEyFhYVEQEhNTAwMSEwMDEVMDACNgENFf6JKEIoKEIoAaAoQif91wGQ/nD3FgwB
J0IolChCKChCKP3DAbGEhAAAAQAxAAAC8wLPABwAADMiJicnATUhMDAxFSM1NDY2MyEyFhYXFQEV
IRUhwTNQDAECKP5ymihCKAGgJD0pBv3YAij9zkEwhgErFEVNKEInHzYik/7VAZkAAAIAGwAAAoEC
0AAkACgAADc1NDY2MzMwMDE1MDAxIRUjNT4CMyEyFhYVFRQGBiMjMDAxFQc1MxWyKEInpf7MmQUo
PiQBRidCKChCJ6Samr5SKEInlmKCIjcgJ0IopihCKEm+mZkAAAEACQAAArECzgAQAAAhMTUhNQEz
FQEzNTMVMxUjFQG4/lEBWor+7N+ZYGCxhwGWU/7Qh4easQAAAf//AAAELALQABAAACExATUzATUn
NTMBETMRIycVAjD9z6ABlNefAZWcn74CnDT+IK3+Nf4eAeL9MOHhAAABAFAAAAR9AtAAEAAAMzER
MxEBMxUHFQEzFQEjNQdQnAGUoNcBk6H9z5+9AtD+HQHjNf6wAeM0/WTh4QABADYAAAL5AtAACAAA
MzERMxEBMxUBNpkBjpz92gLQ/hoB5kD9cAAAAgAAAAACwgLQAAkADQAAMTE1ATMRIzUjBwExMzUC
JZ2a+pIBEnoyAp79MK6uAUeQAAACADYAAAL5AtAACQANAAAzMREzARUjJyMVETEzJzadAiadk/p6
egLQ/WIyrq4BR5AA
FIN_B64
    fi
}

# --- Programme principal ---
MESSAGE="" GARDER_MESSAGE=0 SANS_ABONNEMENT=0 AUTO_MAJ=0 SILENCIEUX=0 REGLAGE_DONNE=0
reglages_actuels   # ce qui est en place est gardé, sauf option contraire
ACTION=menu
[ $# -gt 0 ] && ACTION=installer
while [ $# -gt 0 ]; do
    case "$1" in
        --installer|--install|--auto) ;;   # --install et --auto : noms de la V28
        --desinstaller|--uninstall) ACTION=desinstaller ;;
        --badge|--message)
            case "${2:-}" in
                ""|-h|-v|--installer|--install|--auto|--desinstaller|--uninstall|--badge|--message|--sans-*|\
                --avec-abonnement|--auto-maj|--no-sub|--silencieux|--version|--aide|--help)
                    erreur "$1 attend une valeur (voir --aide)." ;;
                *) ;;
            esac
            if [ "$1" = --badge ]; then BADGE=$2; else MESSAGE=$2 GARDER_MESSAGE=0; fi
            REGLAGE_DONNE=1
            shift ;;
        --sans-message) MESSAGE="" GARDER_MESSAGE=0 REGLAGE_DONNE=1 ;;
        --sans-abonnement|--no-sub) SANS_ABONNEMENT=1 REGLAGE_DONNE=1 ;;
        --avec-abonnement) SANS_ABONNEMENT=0 REGLAGE_DONNE=1 ;;
        --auto-maj) AUTO_MAJ=1 REGLAGE_DONNE=1 ;;
        --sans-auto-maj) AUTO_MAJ=0 REGLAGE_DONNE=1 ;;
        --silencieux) SILENCIEUX=1 ;;
        -v|--version)
            empreinte="inconnue (script lu depuis un tube)"
            if [ -f "$0" ]; then empreinte=$(sha256sum < "$0" | cut -c1-12); fi
            echo "install_theme_proxmox.sh $VERSION_THEME, empreinte $empreinte"
            exit 0 ;;
        -h|--aide|--help) aide; exit 0 ;;
        *) erreur "option inconnue : $1 (voir --aide)." ;;
    esac
    shift
done
if [ "$SILENCIEUX" = 1 ]; then exec >/dev/null 2>&1; fi
[ "$EUID" -eq 0 ] || erreur "ce script se lance en root."
# Un arrêt en cours de route (Ctrl+C) ne laisse aucun fichier temporaire
trap 'rm -f "$INDEX.$MARQUE" "$LIB.$MARQUE" "$SAUVEGARDES/proxmoxlib.js.tmp" "$COPIE.tmp" "$CROCHET~"' EXIT
trap 'exit 130' INT TERM
if [ "$SILENCIEUX" = 1 ]; then
    # Lancé par la remise automatique après un passage d'apt : si le thème est toujours en place et
    # qu'aucun réglage n'est demandé, rien à refaire, et on s'arrête tout de suite (sans lancer pveversion)
    if [ "$ACTION" = installer ] && [ "$REGLAGE_DONNE" = 0 ] && grep -qsF "$MARQUE" "$INDEX" \
        && { [ "$SANS_ABONNEMENT" != 1 ] || grep -qsF "$REPERE_OK" "$LIB"; }; then
        exit 0
    fi
fi
verifier
"$ACTION"   # menu, installer ou desinstaller

# --- Licence de la police Orbitron intégrée ci-dessus (à garder avec ce script) ---
#
# Copyright 2018 The Orbitron Project Authors (https://github.com/theleagueof/orbitron), with Reserved Font Name: "Orbitron"
#
# This Font Software is licensed under the SIL Open Font License, Version 1.1.
# This license is copied below, and is also available with a FAQ at:
# http://scripts.sil.org/OFL
#
#
# -----------------------------------------------------------
# SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
# -----------------------------------------------------------
#
# PREAMBLE
# The goals of the Open Font License (OFL) are to stimulate worldwide
# development of collaborative font projects, to support the font creation
# efforts of academic and linguistic communities, and to provide a free and
# open framework in which fonts may be shared and improved in partnership
# with others.
#
# The OFL allows the licensed fonts to be used, studied, modified and
# redistributed freely as long as they are not sold by themselves. The
# fonts, including any derivative works, can be bundled, embedded,
# redistributed and/or sold with any software provided that any reserved
# names are not used by derivative works. The fonts and derivatives,
# however, cannot be released under any other type of license. The
# requirement for fonts to remain under this license does not apply
# to any document created using the fonts or their derivatives.
#
# DEFINITIONS
# "Font Software" refers to the set of files released by the Copyright
# Holder(s) under this license and clearly marked as such. This may
# include source files, build scripts and documentation.
#
# "Reserved Font Name" refers to any names specified as such after the
# copyright statement(s).
#
# "Original Version" refers to the collection of Font Software components as
# distributed by the Copyright Holder(s).
#
# "Modified Version" refers to any derivative made by adding to, deleting,
# or substituting -- in part or in whole -- any of the components of the
# Original Version, by changing formats or by porting the Font Software to a
# new environment.
#
# "Author" refers to any designer, engineer, programmer, technical
# writer or other person who contributed to the Font Software.
#
# PERMISSION & CONDITIONS
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of the Font Software, to use, study, copy, merge, embed, modify,
# redistribute, and sell modified and unmodified copies of the Font
# Software, subject to the following conditions:
#
# 1) Neither the Font Software nor any of its individual components,
# in Original or Modified Versions, may be sold by itself.
#
# 2) Original or Modified Versions of the Font Software may be bundled,
# redistributed and/or sold with any software, provided that each copy
# contains the above copyright notice and this license. These can be
# included either as stand-alone text files, human-readable headers or
# in the appropriate machine-readable metadata fields within text or
# binary files as long as those fields can be easily viewed by the user.
#
# 3) No Modified Version of the Font Software may use the Reserved Font
# Name(s) unless explicit written permission is granted by the corresponding
# Copyright Holder. This restriction only applies to the primary font name as
# presented to the users.
#
# 4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
# Software shall not be used to promote, endorse or advertise any
# Modified Version, except to acknowledge the contribution(s) of the
# Copyright Holder(s) and the Author(s) or with their explicit written
# permission.
#
# 5) The Font Software, modified or unmodified, in part or in whole,
# must be distributed entirely under this license, and must not be
# distributed under any other license. The requirement for fonts to
# remain under this license does not apply to any document created
# using the Font Software.
#
# TERMINATION
# This license becomes null and void if any of the above conditions are
# not met.
#
# DISCLAIMER
# THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
# OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
# DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
# OTHER DEALINGS IN THE FONT SOFTWARE.
