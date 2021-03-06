# frozen_string_literal: true

Pharos.addon 'kubernetes-dashboard' do
  version '1.8.3'
  license 'Apache License 2.0'

  install {
    apply_resources

    logger.info { "~~> kubernetes-dashboard can be accessed via kubectl proxy at http://localhost:8001/ui" }

    service_account = kube_client.get_service_account('dashboard-admin', 'kube-system')
    token_secret = service_account.secrets[0]
    if token_secret
      logger.info { "~~> kubernetes-dashboard admin token can be fetched using: kubectl describe secret #{token_secret.name} -n kube-system" }
    else
      logger.error { "~~> kubernetes-dashboard admin token cannot be found" }
    end
  }
end
