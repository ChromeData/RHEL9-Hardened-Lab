# RHEL 9 hardening lab box.
#
# Default is almalinux/9 so the lab runs with no Red Hat subscription. Swap BOX
# to a subscribed RHEL 9 box if you want to scan the genuine article — the STIG
# content is the same; only the subscription-manager checks differ.

BOX = ENV.fetch("LAB_BOX", "almalinux/9")

Vagrant.configure("2") do |config|
  config.vm.box = BOX
  config.vm.hostname = "rhel9-hardening-lab"

  # Deliberately do NOT disable the default insecure key here — the point is to
  # watch SSH hardening potentially lock you out, then recover. See LAB-NOTES.
  config.vm.provider "virtualbox" do |vb|
    vb.memory = 2048
    vb.cpus   = 2
  end

  config.vm.provider "libvirt" do |lv|
    lv.memory = 2048
    lv.cpus   = 2
  end

  # Ansible runs from the host against the box.
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "ansible/site.yml"
    ansible.galaxy_role_file = "ansible/requirements.yml"
    ansible.galaxy_roles_path = "ansible/roles"
    ansible.compatibility_mode = "2.0"
  end
end
