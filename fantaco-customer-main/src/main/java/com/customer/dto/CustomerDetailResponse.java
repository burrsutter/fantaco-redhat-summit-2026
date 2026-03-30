package com.customer.dto;

import java.time.LocalDateTime;
import java.util.List;

public record CustomerDetailResponse(
    String customerId,
    String companyName,
    String contactName,
    String contactTitle,
    String address,
    String city,
    String region,
    String postalCode,
    String country,
    String phone,
    String fax,
    String contactEmail,
    String website,
    LocalDateTime createdAt,
    LocalDateTime updatedAt,
    List<CustomerNoteResponse> notes,
    List<CustomerContactResponse> contacts,
    List<SalesPersonResponse> salesPersons
) {}
