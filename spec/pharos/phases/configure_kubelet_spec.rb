require "pharos/config"
require "pharos/phases/configure_kubelet"

describe Pharos::Phases::ConfigureKubelet do
  let(:host) { Pharos::Configuration::Host.new(address: 'test', private_address: '192.168.42.1') }

  let(:config) { Pharos::Config.new(
      hosts: [host],
      network: {},
      addons: {},
      etcd: {}
  ) }
  subject { described_class.new(host, config) }
  let(:ssh_client) { instance_double(Pharos::SSH::Client) }

  before :each do
    allow(Pharos::SSH::Client).to receive(:for_host).and_return(ssh_client)
  end

  describe '#build_systemd_dropin' do
    it "returns a systemd unit" do
      expect(subject.build_systemd_dropin).to eq <<~EOM
        [Service]
        Environment='KUBELET_EXTRA_ARGS=--node-ip=192.168.42.1 --hostname-override='
        Environment='KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local'
        ExecStartPre=-/sbin/swapoff -a
      EOM
    end

    context "with a different network.service_cidr" do
      let(:config) { Pharos::Config.new(
          hosts: [host],
          network: {
            service_cidr: '172.255.0.0/16',
          },
          addons: {},
          etcd: {}
      ) }

      it "uses the customized --cluster-dns" do
        expect(subject.build_systemd_dropin).to eq <<~EOM
          [Service]
          Environment='KUBELET_EXTRA_ARGS=--node-ip=192.168.42.1 --hostname-override='
          Environment='KUBELET_DNS_ARGS=--cluster-dns=172.255.0.10 --cluster-domain=cluster.local'
          ExecStartPre=-/sbin/swapoff -a
        EOM
      end

    end
  end
end