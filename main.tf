// Copyright (c) 2017, 2024, Oracle and/or its affiliates. All rights reserved.
// Licensed under the Mozilla Public License v2.0

variable "ssh_cidr" {
  default = "0.0.0.0/0"
  description = "You can set this to limit access to SSH."
}

variable "acore_realm" {
  default = "AzerothCore"
  description = "Name of the AzerothCore realm."
}

# variable "dr_region" {
#   description = "The region in which you want to store a DR database backups."
# }

//    * DOMAIN_ENDPOINT    - the domain endpoint
// 	  	    To find Domain URL, navigate to Identity > Domains in OCI console, choose relevant domain,
// 			then in the overview page, find "Domain URL" under "Domain Information", click "Copy".
// 			Should look like: domain_endpoint=https://idcs-...identity.oraclecloud.com.

variable "tenancy_ocid" {
  description = "This value will be populated by Resource Manager when used via web portal."
}

variable "compartment_ocid" {
  description = "This value will be populated by Resource Manager when used via web portal."
}

variable "region" {
  description = "This value will be populated by Resource Manager when used via web portal."
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  region           = var.region
}

resource "oci_identity_tag_namespace" "tag-namespace1" {
  #Required
  compartment_id = var.tenancy_ocid
  description    = "AzerothCore namespace"
  name           = "acore"
}

resource "oci_identity_tag" "tag1" {
  #Required
  description      = "AzerothCore realm tag"
  name             = "realm"
  tag_namespace_id = oci_identity_tag_namespace.tag-namespace1.id
}

resource "oci_identity_domains_dynamic_resource_group" "test_dynamic_resource_group" {
  #Required
  display_name  = ""
  idcs_endpoint = data.oci_identity_domain.test_domain.url
  matching_rule = "tag.acore.realm.value='AzerothCore'"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]
}

resource "oci_core_vcn" "vcn1" {
  cidr_block     = "10.0.0.0/16"
  dns_label      = "vcn1"
  compartment_id = var.compartment_ocid
  display_name   = "vcn1"
}

resource "oci_core_internet_gateway" "test_internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "testInternetGateway"
  vcn_id         = oci_core_vcn.vcn1.id
}

resource "oci_core_default_route_table" "default_route_table" {
  manage_default_resource_id = oci_core_vcn.vcn1.default_route_table_id
  display_name               = "defaultRouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.test_internet_gateway.id
  }
}

resource "oci_core_route_table" "route_table1" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn1.id
  display_name   = "routeTable1"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.test_internet_gateway.id
  }
}

resource "oci_core_default_dhcp_options" "default_dhcp_options" {
  manage_default_resource_id = oci_core_vcn.vcn1.default_dhcp_options_id
  display_name               = "defaultDhcpOptions"

  // required
  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusInternet"
  }

}

resource "oci_core_dhcp_options" "dhcp_options1" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn1.id
  display_name   = "dhcpOptions1"

  // required
  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusInternet"
  }

}

resource "oci_core_default_security_list" "default_security_list" {
  manage_default_resource_id = oci_core_vcn.vcn1.default_security_list_id
  display_name               = "defaultSecurityList"

  // allow outbound tcp traffic on all ports
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "6"
  }

  // allow outbound udp traffic on a port range
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "17" // udp
    stateless   = true
  }

  // allow inbound ssh traffic
  ingress_security_rules {
    protocol  = "6" // tcp
    source    = var.ssh_cidr
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol  = "6" // tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 8085
      max = 8085
    }
  }
  
  ingress_security_rules {
    protocol  = "6" // tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 3724
      max = 3724
    }
  }

  // allow inbound icmp traffic of a specific type
  ingress_security_rules {
    protocol  = 1
    source    = "0.0.0.0/0"
    stateless = true

    icmp_options {
      type = 3
      code = 4
    }
  }
}

// A regional subnet will not specify an Availability Domain
resource "oci_core_subnet" "regional_subnet" {
  cidr_block        = "10.0.1.0/24"
  display_name      = "regionalSubnet"
  dns_label         = "regionalsubnet"
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.vcn1.id
  security_list_ids = [oci_core_vcn.vcn1.default_security_list_id]
  route_table_id    = oci_core_vcn.vcn1.default_route_table_id
  dhcp_options_id   = oci_core_vcn.vcn1.default_dhcp_options_id
}