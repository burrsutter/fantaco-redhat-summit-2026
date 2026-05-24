const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { parseRoutesCsv } = require('../routes-csv');

describe('parseRoutesCsv', () => {
  it('parses enabled routes', () => {
    const csv = [
      '# public_host,openshift_route_host,enabled',
      'claw-abc-def123.yougetaclaw.com,claw-abc-def123.apps.ocp.example.com,true',
      'claw-abc-aaa111.yougetaclaw.com,claw-abc-aaa111.apps.ocp.example.com,true',
    ].join('\n');

    const routes = parseRoutesCsv(csv);
    assert.equal(routes.length, 2);
    assert.deepEqual(routes[0], {
      public_host: 'claw-abc-def123.yougetaclaw.com',
      backend_host: 'claw-abc-def123.apps.ocp.example.com',
      enabled: true,
      namespace: '',
    });
  });

  it('skips disabled routes', () => {
    const csv = [
      'claw-abc-def123.yougetaclaw.com,claw-abc-def123.apps.ocp.example.com,false',
      'claw-abc-aaa111.yougetaclaw.com,claw-abc-aaa111.apps.ocp.example.com,true',
    ].join('\n');

    const routes = parseRoutesCsv(csv);
    assert.equal(routes.length, 1);
    assert.equal(routes[0].public_host, 'claw-abc-aaa111.yougetaclaw.com');
  });

  it('skips comments and blank lines', () => {
    const csv = [
      '# this is a comment',
      '',
      '  ',
      'claw-abc-def123.yougetaclaw.com,claw-abc-def123.apps.ocp.example.com,true',
    ].join('\n');

    const routes = parseRoutesCsv(csv);
    assert.equal(routes.length, 1);
  });

  it('trims whitespace from fields', () => {
    const csv = '  claw-abc-def123.yougetaclaw.com , claw-abc-def123.apps.ocp.example.com , true  ';
    const routes = parseRoutesCsv(csv);
    assert.equal(routes[0].public_host, 'claw-abc-def123.yougetaclaw.com');
    assert.equal(routes[0].backend_host, 'claw-abc-def123.apps.ocp.example.com');
  });

  it('lowercases hostnames', () => {
    const csv = 'CLAW-ABC-DEF123.yougetaclaw.com,CLAW-ABC-DEF123.apps.ocp.example.com,TRUE';
    const routes = parseRoutesCsv(csv);
    assert.equal(routes[0].public_host, 'claw-abc-def123.yougetaclaw.com');
    assert.equal(routes[0].enabled, true);
  });

  it('rejects invalid hostnames', () => {
    const csv = 'not a valid host!,also bad!,true';
    const routes = parseRoutesCsv(csv);
    assert.equal(routes.length, 0);
  });

  it('returns empty array for empty input', () => {
    assert.deepEqual(parseRoutesCsv(''), []);
    assert.deepEqual(parseRoutesCsv('# only comments'), []);
  });
});
