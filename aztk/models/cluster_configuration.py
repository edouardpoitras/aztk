from aztk.core.models import Model, fields
import aztk.error as error
from aztk.utils import helpers, deprecate

from .file_share import FileShare
from .toolkit import Toolkit
from .custom_script import CustomScript
from .plugins import PluginConfiguration
from .user_configuration import UserConfiguration

class ClusterConfiguration(Model):
    """
    Cluster configuration model

    Args:
        toolkit
    """
    cluster_id = fields.String()
    toolkit = fields.Model(Toolkit)
    size = fields.Integer(default=0)
    size_low_pri = fields.Integer(default=0)
    vm_size = fields.String()

    subnet_id = fields.String()
    plugins = fields.List(PluginConfiguration)
    custom_scripts = fields.List(CustomScript)
    file_shares = fields.List(FileShare)
    user_configuration = fields.Model(UserConfiguration)

    def __init__(self, *args, **kwargs):
        if 'vm_count' in kwargs:
            deprecate("vm_count is deprecated for ClusterConfiguration please use size instead")
            kwargs['size'] = kwargs.pop('vm_count')

        if 'vm_low_pri_count' in kwargs:
            deprecate("vm_low_pri_count is deprecated for ClusterConfiguration please use size_low_pri instead")
            kwargs['size_low_pri'] = kwargs.pop('vm_low_pri_count')

        super().__init__(*args, **kwargs)

    def mixed_mode(self) -> bool:
        return self.size > 0 and self.size_low_pri > 0


    def gpu_enabled(self):
        return helpers.is_gpu_enabled(self.vm_size)

    def get_docker_repo(self):
        return self.toolkit.get_docker_repo(self.gpu_enabled())

    def __validate__(self) -> bool:
        if self.size == 0 and self.size_low_pri == 0:
            raise error.InvalidModelError(
                "Please supply a valid (greater than 0) size or size_low_pri value either in the cluster.yaml configuration file or with a parameter (--size or --size-low-pri)"
            )

        if self.vm_size is None:
            raise error.InvalidModelError(
                "Please supply a vm_size in either the cluster.yaml configuration file or with a parameter (--vm-size)"
            )

        if self.mixed_mode() and not self.subnet_id:
            raise error.InvalidModelError(
                "You must configure a VNET to use AZTK in mixed mode (dedicated and low priority nodes). Set the VNET's subnet_id in your cluster.yaml."
            )

        if self.custom_scripts:
            deprecate("Custom scripts are DEPRECATED and will be removed in 0.8.0. Use plugins instead See https://aztk.readthedocs.io/en/v0.7.0/15-plugins.html")
