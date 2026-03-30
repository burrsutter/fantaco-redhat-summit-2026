package com.customer.service;

import com.customer.dto.*;
import com.customer.exception.CustomerNotFoundException;
import com.customer.exception.DuplicateCustomerIdException;
import com.customer.model.Customer;
import com.customer.model.CustomerContact;
import com.customer.model.CustomerNote;
import com.customer.model.SalesPerson;
import com.customer.repository.CustomerRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

@Service
@Transactional
public class CustomerService {

    private final CustomerRepository customerRepository;

    public CustomerService(CustomerRepository customerRepository) {
        this.customerRepository = customerRepository;
    }

    public CustomerResponse createCustomer(CustomerRequest request) {
        // Check for duplicate customer ID
        if (customerRepository.existsById(request.customerId())) {
            throw new DuplicateCustomerIdException("Customer with ID " + request.customerId() + " already exists");
        }

        Customer customer = new Customer();
        customer.setCustomerId(request.customerId());
        customer.setCompanyName(request.companyName());
        customer.setContactName(request.contactName());
        customer.setContactTitle(request.contactTitle());
        customer.setAddress(request.address());
        customer.setCity(request.city());
        customer.setRegion(request.region());
        customer.setPostalCode(request.postalCode());
        customer.setCountry(request.country());
        customer.setPhone(request.phone());
        customer.setFax(request.fax());
        customer.setContactEmail(request.contactEmail());
        customer.setWebsite(request.website());

        try {
            Customer savedCustomer = customerRepository.save(customer);
            return toResponse(savedCustomer);
        } catch (DataIntegrityViolationException e) {
            throw new DuplicateCustomerIdException("Customer with ID " + request.customerId() + " already exists");
        }
    }

    @Transactional(readOnly = true)
    public CustomerResponse getCustomerById(String customerId) {
        Customer customer = customerRepository.findById(customerId)
                .orElseThrow(() -> new CustomerNotFoundException("Customer with ID " + customerId + " not found"));
        return toResponse(customer);
    }

    @Transactional(readOnly = true)
    public List<CustomerResponse> searchCustomers(String companyName, String contactName, String contactEmail, String phone) {
        boolean hasAnyCriteria = (companyName != null && !companyName.isBlank())
                || (contactName != null && !contactName.isBlank())
                || (contactEmail != null && !contactEmail.isBlank())
                || (phone != null && !phone.isBlank());

        if (!hasAnyCriteria) {
            return customerRepository.findAll().stream()
                    .map(this::toResponse)
                    .toList();
        }

        // Start with all customers, then intersect each active filter
        List<Customer> results = null;

        if (companyName != null && !companyName.isBlank()) {
            results = new ArrayList<>(customerRepository.findByCompanyNameContainingIgnoreCase(companyName));
        }
        if (contactName != null && !contactName.isBlank()) {
            List<Customer> matched = customerRepository.findByContactNameContainingIgnoreCase(contactName);
            results = (results == null) ? new ArrayList<>(matched) : intersect(results, matched);
        }
        if (contactEmail != null && !contactEmail.isBlank()) {
            List<Customer> matched = customerRepository.findByContactEmailContainingIgnoreCase(contactEmail);
            results = (results == null) ? new ArrayList<>(matched) : intersect(results, matched);
        }
        if (phone != null && !phone.isBlank()) {
            List<Customer> matched = customerRepository.findByPhoneContainingIgnoreCase(phone);
            results = (results == null) ? new ArrayList<>(matched) : intersect(results, matched);
        }

        return results.stream()
                .map(this::toResponse)
                .toList();
    }

    private List<Customer> intersect(List<Customer> a, List<Customer> b) {
        List<Customer> result = new ArrayList<>(a);
        result.retainAll(b);
        return result;
    }

    public CustomerResponse updateCustomer(String customerId, CustomerUpdateRequest request) {
        Customer customer = customerRepository.findById(customerId)
                .orElseThrow(() -> new CustomerNotFoundException("Customer with ID " + customerId + " not found"));

        customer.setCompanyName(request.companyName());
        customer.setContactName(request.contactName());
        customer.setContactTitle(request.contactTitle());
        customer.setAddress(request.address());
        customer.setCity(request.city());
        customer.setRegion(request.region());
        customer.setPostalCode(request.postalCode());
        customer.setCountry(request.country());
        customer.setPhone(request.phone());
        customer.setFax(request.fax());
        customer.setContactEmail(request.contactEmail());
        customer.setWebsite(request.website());

        Customer updatedCustomer = customerRepository.save(customer);
        return toResponse(updatedCustomer);
    }

    public void deleteCustomer(String customerId) {
        if (!customerRepository.existsById(customerId)) {
            throw new CustomerNotFoundException("Customer with ID " + customerId + " not found");
        }
        customerRepository.deleteById(customerId);
    }

    @Transactional(readOnly = true)
    public CustomerDetailResponse getCustomerDetailById(String customerId) {
        Customer customer = customerRepository.findById(customerId)
                .orElseThrow(() -> new CustomerNotFoundException("Customer with ID " + customerId + " not found"));
        return toDetailResponse(customer);
    }

    private CustomerDetailResponse toDetailResponse(Customer customer) {
        List<CustomerNoteResponse> noteResponses = customer.getNotes().stream()
                .map(note -> new CustomerNoteResponse(
                        note.getId(),
                        customer.getCustomerId(),
                        note.getNoteText(),
                        note.getCreatedAt(),
                        note.getUpdatedAt()
                ))
                .toList();

        List<CustomerContactResponse> contactResponses = customer.getContacts().stream()
                .map(contact -> new CustomerContactResponse(
                        contact.getId(),
                        customer.getCustomerId(),
                        contact.getFirstName(),
                        contact.getLastName(),
                        contact.getEmail(),
                        contact.getTitle(),
                        contact.getPhone(),
                        contact.getNotes(),
                        contact.getCreatedAt(),
                        contact.getUpdatedAt()
                ))
                .toList();

        List<SalesPersonResponse> salesPersonResponses = customer.getSalesPersons().stream()
                .map(sp -> new SalesPersonResponse(
                        sp.getId(),
                        customer.getCustomerId(),
                        sp.getFirstName(),
                        sp.getLastName(),
                        sp.getEmail(),
                        sp.getPhone(),
                        sp.getTerritory(),
                        sp.getCreatedAt(),
                        sp.getUpdatedAt()
                ))
                .toList();

        return new CustomerDetailResponse(
                customer.getCustomerId(),
                customer.getCompanyName(),
                customer.getContactName(),
                customer.getContactTitle(),
                customer.getAddress(),
                customer.getCity(),
                customer.getRegion(),
                customer.getPostalCode(),
                customer.getCountry(),
                customer.getPhone(),
                customer.getFax(),
                customer.getContactEmail(),
                customer.getWebsite(),
                customer.getCreatedAt(),
                customer.getUpdatedAt(),
                noteResponses,
                contactResponses,
                salesPersonResponses
        );
    }

    private CustomerResponse toResponse(Customer customer) {
        return new CustomerResponse(
                customer.getCustomerId(),
                customer.getCompanyName(),
                customer.getContactName(),
                customer.getContactTitle(),
                customer.getAddress(),
                customer.getCity(),
                customer.getRegion(),
                customer.getPostalCode(),
                customer.getCountry(),
                customer.getPhone(),
                customer.getFax(),
                customer.getContactEmail(),
                customer.getWebsite(),
                customer.getCreatedAt(),
                customer.getUpdatedAt()
        );
    }
}
