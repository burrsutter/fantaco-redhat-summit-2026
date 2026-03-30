package com.customer.service;

import com.customer.dto.CustomerContactRequest;
import com.customer.dto.CustomerContactResponse;
import com.customer.exception.CustomerNotFoundException;
import com.customer.exception.ResourceNotFoundException;
import com.customer.model.Customer;
import com.customer.model.CustomerContact;
import com.customer.repository.CustomerContactRepository;
import com.customer.repository.CustomerRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class CustomerContactService {

    private final CustomerContactRepository contactRepository;
    private final CustomerRepository customerRepository;

    public CustomerContactService(CustomerContactRepository contactRepository, CustomerRepository customerRepository) {
        this.contactRepository = contactRepository;
        this.customerRepository = customerRepository;
    }

    @Transactional(readOnly = true)
    public List<CustomerContactResponse> getContactsByCustomerId(String customerId) {
        verifyCustomerExists(customerId);
        return contactRepository.findByCustomerCustomerId(customerId).stream()
                .map(this::toResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public CustomerContactResponse getContactById(String customerId, Long contactId) {
        verifyCustomerExists(customerId);
        CustomerContact contact = contactRepository.findById(contactId)
                .orElseThrow(() -> new ResourceNotFoundException("Contact with ID " + contactId + " not found"));
        if (!contact.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Contact with ID " + contactId + " not found for customer " + customerId);
        }
        return toResponse(contact);
    }

    public CustomerContactResponse createContact(String customerId, CustomerContactRequest request) {
        Customer customer = customerRepository.findById(customerId)
                .orElseThrow(() -> new CustomerNotFoundException("Customer with ID " + customerId + " not found"));

        CustomerContact contact = new CustomerContact();
        contact.setFirstName(request.firstName());
        contact.setLastName(request.lastName());
        contact.setEmail(request.email());
        contact.setTitle(request.title());
        contact.setPhone(request.phone());
        contact.setNotes(request.notes());
        contact.setCustomer(customer);

        CustomerContact saved = contactRepository.save(contact);
        return toResponse(saved);
    }

    public CustomerContactResponse updateContact(String customerId, Long contactId, CustomerContactRequest request) {
        verifyCustomerExists(customerId);
        CustomerContact contact = contactRepository.findById(contactId)
                .orElseThrow(() -> new ResourceNotFoundException("Contact with ID " + contactId + " not found"));
        if (!contact.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Contact with ID " + contactId + " not found for customer " + customerId);
        }

        contact.setFirstName(request.firstName());
        contact.setLastName(request.lastName());
        contact.setEmail(request.email());
        contact.setTitle(request.title());
        contact.setPhone(request.phone());
        contact.setNotes(request.notes());

        CustomerContact updated = contactRepository.save(contact);
        return toResponse(updated);
    }

    public void deleteContact(String customerId, Long contactId) {
        verifyCustomerExists(customerId);
        CustomerContact contact = contactRepository.findById(contactId)
                .orElseThrow(() -> new ResourceNotFoundException("Contact with ID " + contactId + " not found"));
        if (!contact.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Contact with ID " + contactId + " not found for customer " + customerId);
        }
        contactRepository.delete(contact);
    }

    private void verifyCustomerExists(String customerId) {
        if (!customerRepository.existsById(customerId)) {
            throw new CustomerNotFoundException("Customer with ID " + customerId + " not found");
        }
    }

    private CustomerContactResponse toResponse(CustomerContact contact) {
        return new CustomerContactResponse(
                contact.getId(),
                contact.getCustomer().getCustomerId(),
                contact.getFirstName(),
                contact.getLastName(),
                contact.getEmail(),
                contact.getTitle(),
                contact.getPhone(),
                contact.getNotes(),
                contact.getCreatedAt(),
                contact.getUpdatedAt()
        );
    }
}
