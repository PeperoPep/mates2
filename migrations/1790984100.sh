echo "Trust Arch Linux ARM's packages on aarch64 installs"

# Installs from the N1x images lack archlinuxarm-keyring, so pacman distrusts
# the Arch Linux ARM build key and refuses every package signed with it, Arch
# Linux ARM updates included. Trust that key (68B3537F…, the one the keyring
# package itself lists as trusted) to install the keyring, which then
# populates the rest.
if [[ $(uname -m) != aarch64 ]] || pacman -Q archlinuxarm-keyring &>/dev/null; then
  exit 0
fi

alarm_build_key=68B3537F39A313B3E574D06777193F152BDBE6A6

if ! sudo pacman-key --list-keys "$alarm_build_key" &>/dev/null; then
  sudo pacman-key --recv-keys "$alarm_build_key"
fi

sudo pacman-key --lsign-key "$alarm_build_key"
sudo pacman -S --noconfirm --needed archlinuxarm-keyring
