package com.customer.dto;

import jakarta.validation.constraints.*;

public record CustomerRequest(
    @NotBlank(message = "Customer ID is required")
    @Size(max = 10, message = "Customer ID must not exceed 10 characters")
    String customerId,

    @NotBlank(message = "Company name is required")
    @Size(max = 60, message = "Company name must not exceed 60 characters")
    String companyName,

    @Size(max = 30, message = "Contact name must not exceed 30 characters")
    String contactName,

    @Size(max = 30, message = "Contact title must not exceed 30 characters")
    String contactTitle,

    @Size(max = 255, message = "Address must not exceed 255 characters")
    String address,

    @Size(max = 15, message = "City must not exceed 15 characters")
    String city,

    @Size(max = 15, message = "Region must not exceed 15 characters")
    String region,

    @Size(max = 10, message = "Postal code must not exceed 10 characters")
    String postalCode,

    @Size(max = 15, message = "Country must not exceed 15 characters")
    String country,

    @Size(max = 24, message = "Phone must not exceed 24 characters")
    String phone,

    @Size(max = 24, message = "Fax must not exceed 24 characters")
    String fax,

    @Email(message = "Contact email must be valid")
    @Size(max = 255, message = "Contact email must not exceed 255 characters")
    String contactEmail,

    @Size(max = 255, message = "Website must not exceed 255 characters")
    String website
) {}
