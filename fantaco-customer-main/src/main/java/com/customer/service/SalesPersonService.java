package com.customer.service;

import com.customer.dto.SalesPersonRequest;
import com.customer.dto.SalesPersonResponse;
import com.customer.exception.CustomerNotFoundException;
import com.customer.exception.ResourceNotFoundException;
import com.customer.model.Customer;
import com.customer.model.SalesPerson;
import com.customer.repository.CustomerRepository;
import com.customer.repository.SalesPersonRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class SalesPersonService {

    private final SalesPersonRepository salesPersonRepository;
    private final CustomerRepository customerRepository;

    public SalesPersonService(SalesPersonRepository salesPersonRepository, CustomerRepository customerRepository) {
        this.salesPersonRepository = salesPersonRepository;
        this.customerRepository = customerRepository;
    }

    @Transactional(readOnly = true)
    public List<SalesPersonResponse> getSalesPersonsByCustomerId(String customerId) {
        verifyCustomerExists(customerId);
        return salesPersonRepository.findByCustomerCustomerId(customerId).stream()
                .map(this::toResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public SalesPersonResponse getSalesPersonById(String customerId, Long salesPersonId) {
        verifyCustomerExists(customerId);
        SalesPerson salesPerson = salesPersonRepository.findById(salesPersonId)
                .orElseThrow(() -> new ResourceNotFoundException("Sales person with ID " + salesPersonId + " not found"));
        if (!salesPerson.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Sales person with ID " + salesPersonId + " not found for customer " + customerId);
        }
        return toResponse(salesPerson);
    }

    public SalesPersonResponse createSalesPerson(String customerId, SalesPersonRequest request) {
        Customer customer = customerRepository.findById(customerId)
                .orElseThrow(() -> new CustomerNotFoundException("Customer with ID " + customerId + " not found"));

        SalesPerson salesPerson = new SalesPerson();
        salesPerson.setFirstName(request.firstName());
        salesPerson.setLastName(request.lastName());
        salesPerson.setEmail(request.email());
        salesPerson.setPhone(request.phone());
        salesPerson.setTerritory(request.territory());
        salesPerson.setCustomer(customer);

        SalesPerson saved = salesPersonRepository.save(salesPerson);
        return toResponse(saved);
    }

    public SalesPersonResponse updateSalesPerson(String customerId, Long salesPersonId, SalesPersonRequest request) {
        verifyCustomerExists(customerId);
        SalesPerson salesPerson = salesPersonRepository.findById(salesPersonId)
                .orElseThrow(() -> new ResourceNotFoundException("Sales person with ID " + salesPersonId + " not found"));
        if (!salesPerson.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Sales person with ID " + salesPersonId + " not found for customer " + customerId);
        }

        salesPerson.setFirstName(request.firstName());
        salesPerson.setLastName(request.lastName());
        salesPerson.setEmail(request.email());
        salesPerson.setPhone(request.phone());
        salesPerson.setTerritory(request.territory());

        SalesPerson updated = salesPersonRepository.save(salesPerson);
        return toResponse(updated);
    }

    public void deleteSalesPerson(String customerId, Long salesPersonId) {
        verifyCustomerExists(customerId);
        SalesPerson salesPerson = salesPersonRepository.findById(salesPersonId)
                .orElseThrow(() -> new ResourceNotFoundException("Sales person with ID " + salesPersonId + " not found"));
        if (!salesPerson.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Sales person with ID " + salesPersonId + " not found for customer " + customerId);
        }
        salesPersonRepository.delete(salesPerson);
    }

    private void verifyCustomerExists(String customerId) {
        if (!customerRepository.existsById(customerId)) {
            throw new CustomerNotFoundException("Customer with ID " + customerId + " not found");
        }
    }

    private SalesPersonResponse toResponse(SalesPerson salesPerson) {
        return new SalesPersonResponse(
                salesPerson.getId(),
                salesPerson.getCustomer().getCustomerId(),
                salesPerson.getFirstName(),
                salesPerson.getLastName(),
                salesPerson.getEmail(),
                salesPerson.getPhone(),
                salesPerson.getTerritory(),
                salesPerson.getCreatedAt(),
                salesPerson.getUpdatedAt()
        );
    }
}
