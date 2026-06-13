variable "vm_size_tier" {
  description = "T-shirt size selected by the user in the AAP JT survey."
  type        = string
  default     = "medium"

  validation {
    condition     = contains(["small", "medium", "large"], var.vm_size_tier)
    error_message = "vm_size_tier must be one of: small, medium, large."
  }
}

variable "linux_admin_username" {
  description = "Admin username on the EC2 instance."
  type        = string
  default     = "ec2-user"
}

variable "linux_ssh_public_key" {
  description = "SSH public key content (e.g. from ~/.ssh/id_rsa.pub) injected into the EC2 instance."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR for the demo VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the single public subnet."
  type        = string
  default     = "10.50.1.0/24"
}

variable "allowed_source_cidrs" {
  description = "Source CIDRs allowed inbound for SSH / HTTP. Default is open; tighten for real use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "lightspeed-patching"
    ManagedBy   = "terraform"
  }
}
