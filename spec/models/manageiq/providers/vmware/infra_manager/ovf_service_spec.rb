require 'vsphere-automation-vcenter'

describe(ManageIQ::Providers::Vmware::InfraManager::OvfService) do
  let(:action) { ResourceAction::PROVISION }
  let(:ovf_template) { FactoryBot.create(:orchestration_template_vmware_infra) }

  let(:ems) { FactoryBot.create(:ems_vmware) }

  let(:service) do
    FactoryBot.create(:service_ovf, :options => config_info_options.merge(dialog_options)).tap do |svc|
      allow(svc).to receive(:manager).and_return(ems)
    end
  end

  let(:loaded_service) do
    service_template = FactoryBot.create(:service_template_ovf).tap do |st|
      allow(st).to receive(:manager).and_return(ems)
    end

    FactoryBot.create(:service_ovf,
                      :options          => {:provision_options => provision_options}.merge(config_info_options),
                      :service_template => service_template).tap do |svc|
      allow(svc).to receive(:ovf_template).and_return(ovf_template)
    end
  end

  let(:dialog_options) do
    {
      :dialog => {
        "dialog_vm_name"       => "dialog_vm_name",
        "dialog_resource_pool" => "5 test resource pool",
        "dialog_ems_folder"    => "30 lucy",
      }
    }
  end

  let(:config_info_options) do
    {
      :config_info => {
        :provision => {
          :dialog_id       => "2",
          :ovf_template_id => ovf_template.id,
          :vm_name         => "template_vm_name",
          :accept_all_EULA => true,
          :resource_pool   => "2 Default for Cluster dev-vc67-cluster",
          :ems_folder      => "3 test_folder",
          :host            => "1 test_host"
        }
      }
    }
  end

  let(:override_options) { {:vm_name => 'override_vm_name'} }

  let(:provision_options) do
    {
      "ovf_template_id"  => ovf_template.id,
      "dialog_id"        => "2",
      "vm_name"          => "dialog_vm_name",
      "accept_all_EULA"  => false,
      "resource_pool_id" => 5,
      "ems_folder_id"    => 30
    }
  end

  let(:failed_response )  { {:value => {:succeeded => false, :error=>{:errors=>[{:category=>"SERVER", :error=>{:@class=>"com.vmware.vapi.std.errors.already_exists", :messages=>[{:args=>["VirtualMachine", "lucy-api-vm-2"], :default_message=>"An object of type \"VirtualMachine\" named \"lucy-api-vm-2\" already exists.", :id=>"com.vmware.vdcs.util.duplicate_name"}]}}], :warnings=>[], :information=>[]}}} }

  let(:deploy_task) { FactoryBot.create(:miq_task, :state => "Active")}

  describe '#preprocess' do
    it 'prepares job options from dialog' do
      service.preprocess(action)
      expect(service.options[:provision_options]).to match a_hash_including(provision_options)
    end

    it 'prepares job options combined from dialog and overrides' do
      service.preprocess(action, override_options)
      expect(service.options[:provision_options]).to match a_hash_including(
        "vm_name" => override_options[:vm_name]
      )
    end
  end

  describe '#deploy_library_item' do
    it 'Provisions with an ovf template' do
      expect(ovf_template).to receive(:deploy) do |options|
        expect(options).to eq(provision_options)
        failed_response
      end
      loaded_service.deploy_library_item(action)
    end
  end

  describe '#check_completed' do
    it 'created VM ends in VMDB' do
      deploy_task.update(:state => "Finished")
      loaded_service.update(:options => loaded_service.options.merge(:deploy_task_id => deploy_task.id))
      loaded_service.update(:options => loaded_service.options.merge(:deploy_response => failed_response))
      expect(loaded_service.check_completed(action)).to eq([true, failed_response.dig(:value, :error).to_json])
    end

    it 'created VM not ends in VMDB yet' do
      loaded_service.update(:options => loaded_service.options.merge(:deploy_task_id => deploy_task.id))
      expect(loaded_service.check_completed(action)).to eq([false, nil])
    end
  end

  describe '#check_refreshed' do
    it 'successful deployment response ' do
      response = {:value => {:succeeded => true, :resource_id=>{:type=>"VirtualMachine", :id=>"vm-934"}}}
      loaded_service.update(:options => loaded_service.options.merge(:deploy_response => response))
      expect(loaded_service.check_refreshed(action)).to eq([false, nil])

      FactoryBot.create(:vm_vmware, :ems_ref_type => "VirtualMachine", :ems_ref => "vm-934", :ems_id => ems.id)
      expect(loaded_service.check_refreshed(action)).to eq([true, nil])
    end

    it 'no successful deployment response ' do
      response = {:value => {:succeeded => false}}
      loaded_service.update(:options => loaded_service.options.merge(:deploy_response => response))
      expect(loaded_service.check_refreshed(action)).to eq([true, nil])
    end

    it 'no deployment response' do
      expect(loaded_service.check_refreshed(action)).to eq([true, nil])
    end
  end
end
