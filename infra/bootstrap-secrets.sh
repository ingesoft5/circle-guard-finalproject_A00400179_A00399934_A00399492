#!/usr/bin/env bash
# HU-01 · Credentials of the platform. Creates every secret of infra/config/secrets.catalog
# that is missing in SSM Parameter Store (SecureString /circleguard/<scope>/<NAME>; dev, stage
# and prod get independent values) and the SSH key pair of each tier. Existing values are
# never overwritten, rotated or printed. Standard SSM parameters and key pairs are not billed.
#
# --target local stores only the tools/* secrets under ~/.circleguard/secrets (outside the
# repository and OneDrive) to validate the tool stacks on Docker Desktop.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"

usage() {
  cat <<'EOF'
Uso: infra/bootstrap-secrets.sh [--plan | --apply] [--target aws|local]
  --plan    (por defecto) lista los secretos y llaves que faltan, sin crear nada.
  --apply   genera solo lo que falta. Nunca sobrescribe ni muestra valores.
  --target local  secretos de las herramientas en ~/.circleguard/secrets (validación local).
EOF
}

# ensure_key_pair <tier>: ED25519 key in $SSH_KEY_DIR, custody copy in SSM, public key in EC2.
ensure_key_pair() {
  local tier=$1 name="$PROJECT-$1" key="$SSH_KEY_DIR/$PROJECT-$1" in_aws have_local=no have_ssm=no aws_fp local_fp
  install -d -m 700 "$SSH_KEY_DIR"
  in_aws=$(aws_ ec2 describe-key-pairs --filters "Name=key-name,Values=$name" --query 'KeyPairs[0].KeyFingerprint' --output text)
  [[ -s "$key" ]] && have_local=yes
  cg_secret_exists ssh "$name" && have_ssm=yes

  if [[ $have_local == no && $have_ssm == yes ]]; then
    if is_apply; then
      (umask 077 && cg_secret_get ssh "$name" >"$key")
      ssh-keygen -y -f "$key" >"$key.pub"
      updated "llave privada $name restaurada desde SSM en $key"
      have_local=yes
    else
      planned "restaurar la llave privada $name desde SSM"
    fi
  elif [[ $have_local == no ]]; then
    nz "$in_aws" && die "El par $name existe en EC2 pero su llave privada no está en $key ni en SSM: recupérela antes de continuar."
    if is_apply; then
      ssh-keygen -q -t ed25519 -N "" -C "$name" -f "$key"
      created "llave SSH $name (ed25519) generada en $key"
      have_local=yes
    else
      planned "generar la llave SSH ed25519 $name"
    fi
  else
    unchanged "llave SSH $name presente en $key"
  fi

  if [[ $have_ssm == yes ]]; then
    unchanged "copia de custodia de $name en SSM (SecureString)"
  elif is_apply; then
    cg_secret_create ssh "$name" <"$key"
    created "copia de custodia de $name en SSM (SecureString)"
  else
    planned "guardar la llave privada $name en SSM (SecureString)"
  fi

  if nz "$in_aws"; then
    if [[ $have_local == yes ]]; then
      aws_fp=${in_aws%%=*}
      local_fp=$(ssh-keygen -lf "$key.pub" -E sha256 | awk '{print $2}')
      local_fp=${local_fp#SHA256:}
      [[ "$aws_fp" == "$local_fp" ]] || warn "la huella del par EC2 $name no coincide con $key.pub"
    fi
    unchanged "par de llaves EC2 $name"
  elif is_apply; then
    aws_ ec2 import-key-pair --key-name "$name" --public-key-material "fileb://$key.pub" \
      --tag-specifications "$(cg_tag_spec key-pair "$name" access "$tier")" >/dev/null
    created "par de llaves EC2 $name importado (solo la llave pública)"
  else
    planned "importar la llave pública $name en EC2"
  fi
}

cg_parse_flags "$@"
cg_load_config
cg_start_log bootstrap-secrets
if [[ "$CG_TARGET" == aws ]]; then
  cg_aws_preflight
else
  require_cmd python3
  info "destino local: secretos en $CG_LOCAL_HOME/secrets (fuera del repositorio y de OneDrive)"
fi

mapfile -t CATALOG < <(cg_catalog)
for entry in "${CATALOG[@]}"; do
  read -r scope name generator <<<"$entry"
  if [[ "$CG_TARGET" == local && "$scope" != tools/* ]]; then continue; fi
  path=$(cg_secret_param "$scope" "$name")
  if cg_secret_exists "$scope" "$name"; then
    unchanged "secreto $path (valor no mostrado)"
  elif is_apply; then
    cg_generate "$generator" | cg_secret_create "$scope" "$name"
    created "secreto $path generado ($generator, valor no mostrado)"
  else
    planned "generar el secreto $path ($generator)"
  fi
done

if [[ "$CG_TARGET" == aws ]]; then
  require_cmd ssh-keygen
  for tier in tools "${CG_ENVS[@]}"; do ensure_key_pair "$tier"; done
fi
cg_summary bootstrap-secrets
